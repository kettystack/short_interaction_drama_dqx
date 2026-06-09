from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import Episode, Highlight, PlaybackProgress, UserEpisodeAction
from ..schemas import EpisodeOut
from ..services import embeddings as emb
from .episodes import episode_to_out

router = APIRouter(prefix="/api/recommendations", tags=["recommendations"])


async def _episode_text(db: AsyncSession, episode: Episode) -> str:
    """组装一段用于嵌入的文本：标题 + 高光类型+描述聚合。"""
    rows = await db.execute(
        select(Highlight).where(Highlight.episode_id == episode.id)
    )
    hl = rows.scalars().all()
    hl_part = " ".join(f"{h.type}:{(h.description or '')[:30]}" for h in hl[:12])
    return f"{episode.title} | {hl_part}"


@router.get("", response_model=list[EpisodeOut])
async def recommend_episodes(user_id: str = "anon", limit: int = 12, db: AsyncSession = Depends(get_db)):
    progress_rows = await db.execute(select(PlaybackProgress).where(PlaybackProgress.user_id == user_id))
    progress = {item.episode_id: item for item in progress_rows.scalars().all()}
    action_rows = await db.execute(
        select(UserEpisodeAction).where(UserEpisodeAction.user_id == user_id, UserEpisodeAction.active.is_(True))
    )
    action_weight = {item.episode_id: 0 for item in action_rows.scalars().all()}
    for episode_id in action_weight:
        action_weight[episode_id] += 8

    episode_rows = await db.execute(select(Episode).order_by(Episode.drama_id, Episode.episode_no))
    scored: list[tuple[float, Episode]] = []
    for episode in episode_rows.scalars().all():
        score = 0.0
        item = progress.get(episode.id)
        if item:
            ratio = item.progress_seconds / item.duration if item.duration else 0
            score += 12 if not item.completed and ratio > 0.08 else 0
            score += 3 if item.completed else 0
        score += action_weight.get(episode.id, 0)
        if not item:
            score += max(0, 6 - episode.episode_no * 0.05)
        scored.append((score, episode))

    scored.sort(key=lambda item: (-item[0], item[1].drama_id, item[1].episode_no))
    return [episode_to_out(episode) for _, episode in scored[: max(1, min(limit, 50))]]


@router.get("/semantic", response_model=list[EpisodeOut])
async def recommend_semantic(
    seed: str,
    limit: int = 10,
    exclude_same_drama: bool = False,
    db: AsyncSession = Depends(get_db),
):
    """语义相似推荐：以 seed 集为种子，按高光语义召回最相近的其它集。

    回退策略：未配置 Doubao Embedding 时自动用本地 char-bigram 向量，保证可用。
    """
    seed_row = await db.execute(select(Episode).where(Episode.id == seed))
    seed_ep = seed_row.scalar_one_or_none()
    if not seed_ep:
        raise HTTPException(404, "seed episode not found")

    seed_vec = await emb.get_vector(seed_ep.id, await _episode_text(db, seed_ep))

    ep_rows = await db.execute(select(Episode))
    eps = [e for e in ep_rows.scalars().all() if e.id != seed_ep.id]
    if exclude_same_drama:
        eps = [e for e in eps if e.drama_id != seed_ep.drama_id]

    scored: list[tuple[float, Episode]] = []
    for ep in eps:
        vec = await emb.get_vector(ep.id, await _episode_text(db, ep))
        scored.append((emb.cosine(seed_vec, vec), ep))
    scored.sort(key=lambda item: -item[0])
    return [episode_to_out(ep) for _, ep in scored[: max(1, min(limit, 30))]]