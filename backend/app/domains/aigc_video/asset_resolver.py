from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ...models import BranchFork, ClipAsset
from .schemas import AigcGenerationContext, ClipCandidate, VideoInsertIntent


async def resolve_clip_asset(
    db: AsyncSession,
    *,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    allow_branch_fallback: bool = True,
) -> ClipCandidate | None:
    clip = await _resolve_from_clip_assets(db, context=context, intent=intent)
    if clip:
        return clip
    if not allow_branch_fallback:
        return None
    return await _resolve_from_same_episode_branches(db, context=context, intent=intent)


async def _resolve_from_clip_assets(
    db: AsyncSession,
    *,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
) -> ClipCandidate | None:
    result = await db.execute(
        select(ClipAsset)
        .where(ClipAsset.episode_id == context.episode_id)
        .where(ClipAsset.status == "enabled")
        .order_by(ClipAsset.ts_start)
    )
    candidates = []
    intent_tokens = _tokens(intent.prompt)
    for clip in result.scalars().all():
        text = " ".join(
            [
                clip.transcript or "",
                clip.location or "",
                " ".join(clip.action_tags or []),
                " ".join(clip.emotion_tags or []),
                " ".join(clip.visual_tags or []),
            ]
        )
        overlap = len(intent_tokens & _tokens(text))
        distance_penalty = abs((clip.ts_start or 0.0) - context.ts_in_video) / 120.0
        quality_bonus = clip.quality_score * 0.5
        score = 0.62 + overlap * 0.08 + quality_bonus - distance_penalty
        candidates.append((score, clip, overlap, distance_penalty))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    score, clip, overlap, distance_penalty = candidates[0]
    reasons = [
        "同集 clip_assets 素材",
        f"语义重合 {overlap}",
        f"时间距离惩罚 {distance_penalty:.2f}",
    ]
    return ClipCandidate(
        clip_id=clip.id,
        clip_url=clip.clip_url,
        episode_id=clip.episode_id,
        drama_id=clip.drama_id,
        ts_start=clip.ts_start,
        ts_end=clip.ts_end,
        duration=clip.duration,
        score=score,
        source="clip_asset",
        provider="asset_resolver",
        match_reasons=reasons,
    )


async def _resolve_from_same_episode_branches(
    db: AsyncSession,
    *,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
) -> ClipCandidate | None:
    result = await db.execute(
        select(BranchFork)
        .where(BranchFork.episode_id == context.episode_id)
        .options(selectinload(BranchFork.branches))
        .order_by(BranchFork.ts_in_video)
    )
    candidates = []
    intent_tokens = _tokens(intent.prompt)
    for fork in result.scalars().all():
        for branch in sorted(fork.branches, key=lambda item: item.order_idx):
            if not branch.video_url:
                continue
            text = f"{fork.prompt_text} {branch.choice_label} {branch.description}"
            overlap = len(intent_tokens & _tokens(text))
            distance_penalty = abs((fork.ts_in_video or 0.0) - context.ts_in_video) / 120.0
            score = 0.52 + overlap * 0.06 - distance_penalty - branch.order_idx * 0.03
            candidates.append((score, fork, branch, overlap, distance_penalty))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    score, fork, branch, overlap, distance_penalty = candidates[0]
    return ClipCandidate(
        clip_id=f"branch_{branch.id}",
        clip_url=branch.video_url,
        episode_id=context.episode_id,
        drama_id=context.drama_id,
        ts_start=fork.ts_in_video,
        ts_end=fork.ts_in_video + (branch.duration or 6.0),
        duration=branch.duration or 6.0,
        score=score,
        source="branch_fallback",
        provider="asset_resolver",
        match_reasons=[
            "同集 branch fallback，仅用于演示兜底",
            f"语义重合 {overlap}",
            f"时间距离惩罚 {distance_penalty:.2f}",
        ],
    )


def _tokens(text: str) -> set[str]:
    return {
        char.lower()
        for char in text
        if char.isalnum() or "\u4e00" <= char <= "\u9fff"
    }
