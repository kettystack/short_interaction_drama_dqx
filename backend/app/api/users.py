from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import PlaybackProgress, UserEpisodeAction
from ..schemas import PlaybackProgressIn, PlaybackProgressOut, UserEpisodeActionIn, UserEpisodeActionOut

router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/{user_id}/progress/{episode_id}", response_model=PlaybackProgressOut | None)
async def get_progress(user_id: str, episode_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PlaybackProgress).where(
            PlaybackProgress.user_id == user_id,
            PlaybackProgress.episode_id == episode_id,
        )
    )
    return result.scalar_one_or_none()


@router.post("/progress", response_model=PlaybackProgressOut)
async def save_progress(payload: PlaybackProgressIn, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PlaybackProgress).where(
            PlaybackProgress.user_id == payload.user_id,
            PlaybackProgress.episode_id == payload.episode_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = PlaybackProgress(user_id=payload.user_id, episode_id=payload.episode_id)
        db.add(item)
    item.progress_seconds = max(payload.progress_seconds, 0)
    item.duration = max(payload.duration, 0)
    item.completed = payload.completed or (item.duration > 0 and item.progress_seconds / item.duration >= 0.92)
    item.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(item)
    return item


@router.get("/{user_id}/actions", response_model=list[UserEpisodeActionOut])
async def list_actions(user_id: str, action: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(UserEpisodeAction).where(UserEpisodeAction.user_id == user_id)
    if action:
        query = query.where(UserEpisodeAction.action == action)
    result = await db.execute(query.order_by(UserEpisodeAction.updated_at.desc()))
    return result.scalars().all()


@router.get("/{user_id}/actions/{episode_id}", response_model=UserEpisodeActionOut | None)
async def get_episode_action(
    user_id: str,
    episode_id: str,
    action: str,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(UserEpisodeAction).where(
            UserEpisodeAction.user_id == user_id,
            UserEpisodeAction.episode_id == episode_id,
            UserEpisodeAction.action == action,
        )
    )
    return result.scalar_one_or_none()


@router.post("/actions", response_model=UserEpisodeActionOut)
async def save_action(payload: UserEpisodeActionIn, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(UserEpisodeAction).where(
            UserEpisodeAction.user_id == payload.user_id,
            UserEpisodeAction.episode_id == payload.episode_id,
            UserEpisodeAction.action == payload.action,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = UserEpisodeAction(user_id=payload.user_id, episode_id=payload.episode_id, action=payload.action)
        db.add(item)
    item.active = payload.active
    item.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(item)
    return item