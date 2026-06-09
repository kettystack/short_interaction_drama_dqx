#!/usr/bin/env python3
"""Create same-episode clip_assets for AIGC boost fallback.

The script cuts short 4-8s clips from the current episode around branch forks or
highlights. These clips are safer AIGC fallback assets than branch videos cut
from later episodes.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import shutil
import subprocess
from pathlib import Path

from sqlalchemy import select

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = PROJECT_ROOT / "backend"
import sys

sys.path.insert(0, str(BACKEND_ROOT))

from app.config import settings  # noqa: E402
from app.database import SessionLocal, init_db  # noqa: E402
from app.models import BranchFork, ClipAsset, Episode, Highlight  # noqa: E402


def resolve_video_path(video_url: str) -> Path | None:
    rel = video_url.removeprefix("/videos/")
    roots: list[tuple[Path, str]] = [(Path(settings.video_root), rel)]
    if rel.startswith("tianxiadyi/"):
        roots.insert(0, (Path(settings.tianxiadyi_video_root), rel.removeprefix("tianxiadyi/")))
    if rel.startswith("shibasuitainainai/"):
        roots.insert(
            0,
            (
                Path(settings.shibasuitainainai_video_root),
                rel.removeprefix("shibasuitainainai/"),
            ),
        )
    for root, relative in roots:
        path = (root / relative).resolve()
        if root.resolve() in path.parents and path.is_file():
            return path
    return None


def run_ffmpeg(source: Path, target: Path, start: float, duration: float) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-ss",
        f"{start:.2f}",
        "-i",
        str(source),
        "-t",
        f"{duration:.2f}",
        "-vf",
        "scale=608:-2",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "23",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        str(target),
    ]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


async def seed_episode(episode_id: str, *, max_clips: int, force: bool) -> int:
    async with SessionLocal() as db:
        episode = await db.get(Episode, episode_id)
        if episode is None:
            raise SystemExit(f"episode not found: {episode_id}")
        source = resolve_video_path(episode.video_url)
        if source is None:
            raise SystemExit(f"video file not found for {episode_id}: {episode.video_url}")

        points: list[tuple[float, str, list[str], list[str]]] = []
        forks = await db.execute(
            select(BranchFork).where(BranchFork.episode_id == episode_id).order_by(BranchFork.ts_in_video)
        )
        for fork in forks.scalars().all():
            points.append((fork.ts_in_video, fork.prompt_text, ["加速", "分支"], ["紧张", "高能"]))
        highlights = await db.execute(
            select(Highlight).where(Highlight.episode_id == episode_id).order_by(Highlight.ts_start)
        )
        for highlight in highlights.scalars().all():
            points.append(
                (
                    highlight.ts_start,
                    highlight.description or highlight.type,
                    [highlight.type, highlight.interaction, "加速"],
                    [highlight.interaction, "高能"],
                )
            )
        if not points:
            points.append((max(episode.duration / 3, 0), episode.title, ["加速"], ["高能"]))

        count = 0
        duration = max(2.0, min(settings.aigc_insert_duration_seconds, 8.0))
        for ts, transcript, action_tags, emotion_tags in points[:max_clips]:
            start = max(ts, 0)
            digest = hashlib.sha1(f"{episode_id}:{start:.2f}:{duration:.2f}".encode("utf-8")).hexdigest()[:10]
            clip_id = f"clip_{episode_id}_{int(start * 1000)}_{digest}"
            relative = Path("clips") / f"{clip_id}.mp4"
            target = Path(settings.generated_media_root) / relative
            if force or not target.is_file():
                run_ffmpeg(source, target, start, duration)
            asset = await db.get(ClipAsset, clip_id)
            if asset is None:
                asset = ClipAsset(id=clip_id)
                db.add(asset)
            asset.drama_id = episode.drama_id
            asset.episode_id = episode.id
            asset.source_video_url = episode.video_url
            asset.clip_url = f"/generated/{relative.as_posix()}"
            asset.ts_start = start
            asset.ts_end = start + duration
            asset.duration = duration
            asset.transcript = transcript or episode.title
            asset.action_tags = action_tags
            asset.emotion_tags = emotion_tags
            asset.visual_tags = ["竖屏短剧", "同集素材", "过渡插片"]
            asset.source = "ffmpeg_seed"
            asset.status = "enabled"
            asset.quality_score = 0.8
            asset.raw = {"seed_reason": "same_episode_aigc_fallback"}
            count += 1
        await db.commit()
        return count


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-id", default="ep_063")
    parser.add_argument("--max-clips", type=int, default=5)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg not found in PATH")
    await init_db()
    count = await seed_episode(args.episode_id, max_clips=args.max_clips, force=args.force)
    print(f"seeded-clip-assets episode={args.episode_id} count={count}")


if __name__ == "__main__":
    asyncio.run(main())
