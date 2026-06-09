#!/usr/bin/env python3
"""Pre-generate and publish playable AIGC boost points.

Default mode uses the current hybrid AIGC service, which falls back to
same-episode clip_assets when the real provider is disabled. Add
``--real-provider`` to submit to Seedance/Jimeng through the configured Ark
endpoint and publish only after the job is ready and passes the quality gate.
"""
from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = PROJECT_ROOT / "backend"
import sys

sys.path.insert(0, str(BACKEND_ROOT))

from app.config import settings  # noqa: E402
from app.database import SessionLocal, init_db  # noqa: E402
from app.domains.aigc_video.schemas import AigcBoostPointCreateIn, AigcVideoJobCreateIn  # noqa: E402
from app.domains.aigc_video.service import AigcVideoService  # noqa: E402
from app.domains.security.schemas import CurrentUser  # noqa: E402


async def create_job(
    *,
    episode_id: str,
    trigger_ts: float,
    prompt: str,
    style_code: str,
    duration_seconds: float,
    force_new: bool,
) -> str:
    user = CurrentUser(user_id="admin", display_name="Admin", role="admin")
    key = None if force_new else f"pregen_boost_{episode_id}_{int(trigger_ts * 1000)}_{style_code}"
    async with SessionLocal() as db:
        service = AigcVideoService(db)
        job = await service.create_job(
            AigcVideoJobCreateIn(
                episode_id=episode_id,
                user_id="admin",
                ts_in_video=trigger_ts,
                trigger_type="boost",
                user_prompt=prompt,
                style_code=style_code,
                duration_seconds=duration_seconds,
                idempotency_key=key,
            ),
            user,
        )
        return job.job_id


async def wait_until_terminal(job_id: str, *, timeout_seconds: int):
    deadline = asyncio.get_running_loop().time() + timeout_seconds
    while True:
        async with SessionLocal() as db:
            service = AigcVideoService(db)
            job = await service.advance_job(job_id)
            print(
                "aigc-job "
                f"id={job.job_id} status={job.status} progress={job.progress:.2f} "
                f"provider={job.provider}"
            )
            if job.status in {"ready", "review_required"}:
                return job
            if job.status == "failed":
                raise SystemExit(f"AIGC job failed: {job.error_message}")
        if asyncio.get_running_loop().time() >= deadline:
            raise SystemExit(f"Timed out waiting for AIGC job: {job_id}")
        await asyncio.sleep(2)


async def approve_review(job_id: str) -> None:
    user = CurrentUser(user_id="admin", display_name="Admin", role="admin")
    async with SessionLocal() as db:
        await AigcVideoService(db).review_job(
            job_id,
            approve=True,
            reviewer=user,
            reason="CLI 显式人工确认通过",
        )


async def publish_boost_point(
    *,
    episode_id: str,
    trigger_ts: float,
    resume_at: float | None,
    title: str,
    job_id: str,
) -> None:
    user = CurrentUser(user_id="admin", display_name="Admin", role="admin")
    async with SessionLocal() as db:
        point = await AigcVideoService(db).create_boost_point(
            AigcBoostPointCreateIn(
                episode_id=episode_id,
                trigger_ts=trigger_ts,
                resume_at=resume_at,
                title=title,
                source_job_id=job_id,
                status="published",
            ),
            user,
        )
        print(
            "published-boost-point "
            f"id={point.id} episode={point.episode_id} "
            f"trigger={point.trigger_ts:.2f}s resume={point.resume_at:.2f}s "
            f"quality={point.quality_score:.3f} output={point.output_video_url}"
        )


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-id", default="ep_063")
    parser.add_argument("--trigger-ts", type=float, default=56.0)
    parser.add_argument("--resume-at", type=float)
    parser.add_argument("--title", default="加速包")
    parser.add_argument(
        "--prompt",
        default="在当前短剧关键节点插入一段高能加速包，保持同一人物、同一地点和竖屏短剧节奏，强化冲突但不改写正片主线。",
    )
    parser.add_argument("--style-code", default="short_drama_punchy")
    parser.add_argument(
        "--duration-seconds",
        type=float,
        default=12.0,
        help="Requested generated clip duration. Current Seedance 1.0 fast endpoint supports up to 12 seconds.",
    )
    parser.add_argument("--job-id", help="Publish an existing ready AIGC job instead of creating a new one.")
    parser.add_argument("--force-new", action="store_true")
    parser.add_argument("--real-provider", action="store_true")
    parser.add_argument("--no-fallback", action="store_true")
    parser.add_argument("--model", help="Override AIGC_VIDEO_MODEL for this run.")
    parser.add_argument("--endpoint-id", help="Use a custom Seedance endpoint id such as ep-xxxx.")
    parser.add_argument(
        "--approve-review",
        action="store_true",
        help="Explicitly approve a review_required candidate before publishing.",
    )
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()

    if args.real_provider:
        settings.aigc_video_real_enabled = True
        settings.aigc_video_provider = "seedance"
    if args.no_fallback:
        settings.aigc_video_fallback_to_assets = False
    if args.model:
        settings.aigc_video_model = args.model
    if args.endpoint_id:
        settings.aigc_video_endpoint_id = args.endpoint_id

    await init_db()
    job_id = args.job_id or await create_job(
        episode_id=args.episode_id,
        trigger_ts=args.trigger_ts,
        prompt=args.prompt,
        style_code=args.style_code,
        duration_seconds=args.duration_seconds,
        force_new=args.force_new,
    )
    job = await wait_until_terminal(job_id, timeout_seconds=args.timeout_seconds)
    if job.status == "review_required":
        print(
            "review-required "
            f"job={job.job_id} quality={job.quality_score:.3f} "
            f"candidate={job.output_video_url} frames={job.review_frames}"
        )
        if not args.approve_review:
            raise SystemExit("Candidate needs human review; it was not published.")
        await approve_review(job_id)
    await publish_boost_point(
        episode_id=args.episode_id,
        trigger_ts=args.trigger_ts,
        resume_at=args.resume_at,
        title=args.title,
        job_id=job_id,
    )


if __name__ == "__main__":
    asyncio.run(main())
