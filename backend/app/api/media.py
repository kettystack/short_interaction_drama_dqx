from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import Episode, EpisodeAsset, TranscodeJob
from ..schemas import EpisodeAssetOut, TranscodeJobOut

router = APIRouter(prefix="/api/media", tags=["media"])


@router.get("/assets/{episode_id}", response_model=list[EpisodeAssetOut])
async def list_assets(episode_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(EpisodeAsset).where(EpisodeAsset.episode_id == episode_id))
    return result.scalars().all()


@router.post("/transcode/{episode_id}", response_model=TranscodeJobOut)
async def enqueue_transcode(episode_id: str, db: AsyncSession = Depends(get_db)):
    episode = await db.get(Episode, episode_id)
    if not episode:
        raise HTTPException(404, "episode not found")
    job = TranscodeJob(
        episode_id=episode_id,
        status="queued",
        source_url=episode.video_url,
        output_url=f"/hls/{episode_id}/master.m3u8",
        updated_at=datetime.utcnow(),
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    return job


@router.get("/transcode/jobs", response_model=list[TranscodeJobOut])
async def list_transcode_jobs(status: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(TranscodeJob)
    if status:
        query = query.where(TranscodeJob.status == status)
    result = await db.execute(query.order_by(TranscodeJob.created_at.desc()).limit(100))
    return result.scalars().all()