from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from ...models import BranchFork, Episode, Highlight
from ..aigc_video.context_builder import build_generation_context
from ..narrative.context_builder import NarrativeContextBuilder
from ..narrative.schemas import BranchGenerationIn
from .manual_context import load_manual_branch_context
from .schemas import BranchVideoContext


async def build_branch_context(
    db: AsyncSession,
    *,
    episode: Episode,
    trigger_source: str,
    trigger_ts: float,
    resume_at: float,
    fork: BranchFork | None = None,
    highlight: Highlight | None = None,
    user_id: str = "anon",
) -> BranchVideoContext:
    narrative = await NarrativeContextBuilder(db).build(
        BranchGenerationIn(
            episode_id=episode.id,
            user_id=user_id,
            ts_in_video=trigger_ts,
            fork_id=fork.id if fork else None,
        )
    )
    generation = await build_generation_context(
        db,
        episode=episode,
        ts_in_video=trigger_ts,
        trigger_type="personalized_branch",
        highlight=highlight,
    )
    events = [*narrative.current_scene_events, *narrative.recent_events]
    active_characters: list[str] = []
    for event in events:
        for character in event.characters:
            if character not in active_characters:
                active_characters.append(character)
    current_conflict = (
        highlight.description
        if highlight and highlight.description
        else events[0].summary
        if events
        else fork.prompt_text
        if fork
        else episode.title
    )
    manual = load_manual_branch_context(
        drama_id=episode.drama_id,
        episode_id=episode.id,
        trigger_source=trigger_source,
        trigger_ts=trigger_ts,
    )
    point_override = manual.get("point") or {}
    series_override = manual.get("series") or {}
    episode_override = manual.get("episode") or {}
    current_conflict = str(
        point_override.get("current_conflict") or current_conflict
    )
    manual_characters = [
        str(item)
        for item in (
            point_override.get("active_characters")
            or episode_override.get("active_characters")
            or series_override.get("main_characters")
            or []
        )
        if str(item).strip()
    ]
    if manual_characters:
        active_characters = manual_characters
    previous_summary = str(
        point_override.get("previous_context")
        or episode_override.get("episode_summary")
        or narrative.previous_summary
    )
    extra_forbidden = [
        str(item)
        for item in (
            series_override.get("forbidden_changes")
            or []
        )
        if str(item).strip()
    ]
    return BranchVideoContext(
        episode_id=episode.id,
        drama_id=episode.drama_id,
        episode_title=episode.title,
        trigger_source=trigger_source,
        trigger_ts=trigger_ts,
        resume_at=resume_at,
        fork_id=fork.id if fork else None,
        highlight_id=highlight.id if highlight else None,
        highlight_type=highlight.type if highlight else "",
        highlight_summary=highlight.description if highlight else "",
        current_conflict=current_conflict,
        recent_events=[event.model_dump(mode="json") for event in events[:8]],
        active_characters=active_characters[:6],
        role_cards=[card.model_dump(mode="json") for card in narrative.role_cards],
        previous_summary=previous_summary,
        source_frame_url=generation.first_frame_url,
        source_frame_path=generation.first_frame_path,
        manual_context=manual,
        forbidden_changes=[
            "不得改变主要角色身份、服装和人物关系",
            "不得跳转到与当前正片无关的地点",
            "不得新增会改写主线事实的关键设定",
            "插片结尾必须允许回到原正片继续播放",
            *extra_forbidden,
        ],
    )
