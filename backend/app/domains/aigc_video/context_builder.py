from __future__ import annotations

import json
import re
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import Episode, Highlight, StoryThreadModel
from .schemas import AigcGenerationContext


_frame_number_re = re.compile(r"_(\d+)\.jpg$")


async def build_generation_context(
    db: AsyncSession,
    *,
    episode: Episode,
    ts_in_video: float,
    trigger_type: str,
    highlight: Highlight | None = None,
    story_thread_id: str | None = None,
) -> AigcGenerationContext:
    resume_at = _resume_at(episode, ts_in_video)
    first_frame = _nearest_frame(episode.id, ts_in_video, prefer_before=True)
    last_frame = _nearest_frame(episode.id, resume_at, prefer_before=False)
    nearby_highlights = await _nearby_highlights(db, episode.id, ts_in_video)
    nearby_events = _nearby_narrative_events(episode.id, ts_in_video)
    branch_path: list[str] = []
    if story_thread_id:
        thread = await db.get(StoryThreadModel, story_thread_id)
        if thread:
            branch_path = [str(item) for item in (thread.branch_path or [])]

    return AigcGenerationContext(
        episode_id=episode.id,
        drama_id=episode.drama_id,
        episode_title=episode.title,
        ts_in_video=max(ts_in_video, 0),
        resume_at=resume_at,
        trigger_type=trigger_type,
        highlight_id=highlight.id if highlight else None,
        highlight_text=_highlight_text(highlight),
        nearby_highlights=nearby_highlights,
        nearby_events=nearby_events,
        branch_path=branch_path,
        story_thread_id=story_thread_id,
        first_frame_url=_public_frame_url(first_frame),
        last_frame_url=_public_frame_url(last_frame),
        first_frame_path=str(first_frame) if first_frame else "",
        last_frame_path=str(last_frame) if last_frame else "",
    )


def _resume_at(episode: Episode, ts_in_video: float) -> float:
    target = max(ts_in_video, 0) + max(settings.aigc_resume_offset_seconds, 0.0)
    if episode.duration and episode.duration > 10:
        return min(target, max(episode.duration - 1.0, 0.0))
    return target


def _frame_root(episode_id: str) -> Path:
    return Path(settings.data_root) / "frames" / episode_id


def _nearest_frame(
    episode_id: str,
    ts_in_video: float,
    *,
    prefer_before: bool,
) -> Path | None:
    root = _frame_root(episode_id)
    if not root.is_dir():
        return None
    frames = sorted(root.glob("*.jpg"))
    if not frames:
        return None
    scored: list[tuple[float, Path]] = []
    for path in frames:
        number = _frame_number(path)
        if number is None:
            continue
        if prefer_before and number > ts_in_video:
            score = (number - ts_in_video) + 1000
        elif not prefer_before and number < ts_in_video:
            score = (ts_in_video - number) + 1000
        else:
            score = abs(number - ts_in_video)
        scored.append((score, path))
    if not scored:
        return frames[0]
    scored.sort(key=lambda item: item[0])
    return scored[0][1]


def _frame_number(path: Path) -> float | None:
    match = _frame_number_re.search(path.name)
    if not match:
        return None
    return float(int(match.group(1)))


def _public_frame_url(path: Path | None) -> str:
    if path is None:
        return ""
    try:
        relative = path.relative_to(Path(settings.data_root) / "frames")
    except ValueError:
        return ""
    return f"{settings.public_base_url.rstrip('/')}/frames/{relative.as_posix()}"


async def _nearby_highlights(
    db: AsyncSession,
    episode_id: str,
    ts_in_video: float,
) -> list[dict]:
    result = await db.execute(
        select(Highlight)
        .where(Highlight.episode_id == episode_id)
        .order_by(Highlight.ts_start)
    )
    items = []
    for item in result.scalars().all():
        distance = min(abs(item.ts_start - ts_in_video), abs(item.ts_end - ts_in_video))
        if distance > 30:
            continue
        items.append(
            {
                "id": item.id,
                "ts_start": item.ts_start,
                "ts_end": item.ts_end,
                "type": item.type,
                "interaction": item.interaction,
                "description": item.description,
                "distance": distance,
            }
        )
    return sorted(items, key=lambda item: item["distance"])[:5]


def _nearby_narrative_events(episode_id: str, ts_in_video: float) -> list[dict]:
    path = Path(settings.data_root) / "narrative_events" / f"{episode_id}.json"
    if not path.is_file():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    events = []
    for event in payload.get("events", []):
        start = float(event.get("ts_start") or event.get("start") or 0)
        end = float(event.get("ts_end") or event.get("end") or start)
        distance = min(abs(start - ts_in_video), abs(end - ts_in_video))
        if distance <= 35:
            events.append({**event, "distance": distance})
    return sorted(events, key=lambda item: item["distance"])[:5]


def _highlight_text(highlight: Highlight | None) -> str:
    if highlight is None:
        return ""
    return (
        f"{highlight.type} / {highlight.interaction}："
        f"{highlight.description}（{highlight.ts_start:.1f}-{highlight.ts_end:.1f}s）"
    )


def require_frame_context(context: AigcGenerationContext) -> None:
    if not context.first_frame_url and not context.first_frame_path:
        raise HTTPException(400, "当前剧集缺少正片首帧，无法提交图生视频")
