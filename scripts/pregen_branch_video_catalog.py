#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path

from sqlalchemy import select

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.app.database import SessionLocal
from backend.app.domains.branch_video.repository import BranchVideoRepository
from backend.app.domains.branch_video.service import BranchVideoService
from backend.app.domains.branch_video.worker import BranchVideoWorker
from backend.app.domains.security.schemas import CurrentUser
from backend.app.models import Episode, PersonalizedBranchOption, PersonalizedBranchSession


CATALOG_USER = CurrentUser(
    user_id="branch-catalog-tianxiadyi",
    display_name="天下第一分支素材库",
    role="admin",
)


class CatalogBillingError(RuntimeError):
    pass


async def prepare_targets(
    *,
    prefix: str,
    episode_id: str,
    options_per_point: int,
    episode_limit: int,
) -> list[tuple[str, str, str]]:
    async with SessionLocal() as db:
        episodes = list(
            (
                await db.execute(
                    select(Episode)
                    .where(Episode.id.like(f"{prefix}%"))
                    .order_by(Episode.id)
                )
            )
            .scalars()
            .all()
        )
    if episode_id:
        episodes = [episode for episode in episodes if episode.id == episode_id]
    if episode_limit > 0:
        episodes = episodes[:episode_limit]

    episode_points: list[tuple[str, str, list[str]]] = []
    for episode in episodes:
        async with SessionLocal() as db:
            sessions = await BranchVideoService(db).ensure_episode_sessions(
                episode_id=episode.id,
                user=CATALOG_USER,
            )
            persisted = {
                session.session_id: await db.get(
                    PersonalizedBranchSession,
                    session.session_id,
                )
                for session in sessions
            }
        content = next(
            (
                session
                for session in sessions
                if (
                    persisted.get(session.session_id)
                    and (
                        persisted[session.session_id].context_snapshot or {}
                    ).get("manual_context")
                )
            ),
            next(
                (
                    session
                    for session in sessions
                    if session.trigger_source != "episode_tail"
                ),
                sessions[0] if sessions else None,
            ),
        )
        if content is None:
            continue
        episode_points.append(
            (
                episode.id,
                content.session_id,
                [option.id for option in content.options[:options_per_point]],
            )
        )
    targets: list[tuple[str, str, str]] = []
    for option_index in range(options_per_point):
        for episode_id, session_id, option_ids in episode_points:
            if option_index < len(option_ids):
                targets.append((episode_id, session_id, option_ids[option_index]))
    return targets


async def generate_target(
    target: tuple[str, str, str],
    *,
    semaphore: asyncio.Semaphore,
    poll_seconds: float,
    max_attempts: int,
    poll_existing_only: bool,
    manifest: "ProgressManifest",
) -> None:
    episode_id, session_id, option_id = target
    async with semaphore:
        while True:
            async with SessionLocal() as db:
                repo = BranchVideoRepository(db)
                session = await repo.get_session(session_id)
                option = await repo.get_option(option_id)
                if session is None or option is None:
                    manifest.update(option_id, episode_id, "failed", "session or option missing")
                    return
                published = await repo.published_variant(option.id)
                if published and published.output_video_url:
                    manifest.update(
                        option.id,
                        episode_id,
                        "ready",
                        option.label,
                        video_url=published.output_video_url,
                        quality_score=published.quality_score,
                    )
                    return
                attempts = int(
                    (option.intent or {}).get("_generation_attempt") or 0
                )
                billing_failure = (
                    "账户余额不足" in str(option.error_message or "")
                    or "AccountOverdueError" in str(option.error_message or "")
                )
                if poll_existing_only and option.status in {"planned", "failed"}:
                    manifest.update(
                        option.id,
                        episode_id,
                        option.status,
                        option.error_message or option.label,
                    )
                    return
                if (
                    option.status == "failed"
                    and attempts >= max_attempts
                    and not billing_failure
                ):
                    manifest.update(
                        option.id,
                        episode_id,
                        "failed",
                        option.error_message or f"generation failed after {attempts} attempts",
                    )
                    return
                if option.status in {"planned", "failed"}:
                    manifest.update(option.id, episode_id, "submitting", option.label)
                    await BranchVideoWorker(db).generate_option(
                        session=session,
                        option=option,
                        user=CATALOG_USER,
                        target_duration=float(
                            (session.context_snapshot or {}).get("target_duration")
                            or 12.0
                        ),
                    )
                else:
                    await BranchVideoWorker(db).sync_option(option)
                await db.refresh(option)
                status = option.status
                message = option.error_message or option.label
                manifest.update(option.id, episode_id, status, message)
                if "账户余额不足" in message or "AccountOverdueError" in message:
                    raise CatalogBillingError(
                        "Seedance 账户余额不足，批处理已暂停；充值后使用同一命令断点续跑"
                    )
                if status == "failed":
                    attempts = int(
                        (option.intent or {}).get("_generation_attempt") or 0
                    )
                    if attempts >= max_attempts:
                        return
                elif status in {"ready", "review_required"}:
                    return
            await asyncio.sleep(poll_seconds)


class ProgressManifest:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.items: dict[str, dict] = {}
        if path.is_file():
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
                self.items = dict(payload.get("items") or {})
            except (OSError, json.JSONDecodeError):
                pass

    def update(
        self,
        option_id: str,
        episode_id: str,
        status: str,
        message: str,
        *,
        video_url: str = "",
        quality_score: float = 0.0,
    ) -> None:
        self.items[option_id] = {
            "episode_id": episode_id,
            "status": status,
            "message": message[:500],
            "video_url": video_url,
            "quality_score": round(float(quality_score or 0.0), 4),
            "updated_at": datetime.now().isoformat(timespec="seconds"),
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(
            json.dumps(
                {
                    "catalog_user": CATALOG_USER.user_id,
                    "updated_at": datetime.now().isoformat(timespec="seconds"),
                    "items": self.items,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(
            f"[{status:>15}] {episode_id} {option_id} {message[:80]}",
            flush=True,
        )


async def run(args: argparse.Namespace) -> None:
    targets = await prepare_targets(
        prefix=args.prefix,
        episode_id=args.episode_id,
        options_per_point=args.options_per_point,
        episode_limit=args.episode_limit,
    )
    print(
        f"prepared {len(targets)} variants from "
        f"{len({item[0] for item in targets})} episodes",
        flush=True,
    )
    if args.dry_run:
        for target in targets:
            print("\t".join(target))
        return
    manifest = ProgressManifest(Path(args.manifest))
    semaphore = asyncio.Semaphore(max(args.concurrency, 1))
    try:
        await asyncio.gather(
            *[
                generate_target(
                    target,
                    semaphore=semaphore,
                    poll_seconds=args.poll_seconds,
                    max_attempts=max(args.max_attempts, 1),
                    poll_existing_only=args.poll_existing_only,
                    manifest=manifest,
                )
                for target in targets
            ]
        )
    except CatalogBillingError as exc:
        print(f"[billing-paused] {exc}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", default="txy_")
    parser.add_argument("--episode-id", default="")
    parser.add_argument("--options-per-point", type=int, default=3)
    parser.add_argument("--episode-limit", type=int, default=0)
    parser.add_argument("--concurrency", type=int, default=3)
    parser.add_argument("--poll-seconds", type=float, default=12.0)
    parser.add_argument("--max-attempts", type=int, default=2)
    parser.add_argument("--poll-existing-only", action="store_true")
    parser.add_argument(
        "--manifest",
        default="data/generated/branch_catalog/tianxiadyi_progress.json",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
