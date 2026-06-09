from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.aigc_video.schemas import (
    AigcBoostPointCreateIn,
    AigcBoostPointOut,
    AigcVideoJobCreateIn,
    AigcVideoJobOut,
    AigcVideoReviewIn,
)
from ..domains.aigc_video.service import AigcVideoService
from ..domains.security.auth import get_current_user, require_admin
from ..domains.security.schemas import CurrentUser

router = APIRouter(prefix="/api/aigc-video", tags=["aigc-video"])


@router.post("/jobs", response_model=AigcVideoJobOut)
async def create_aigc_video_job(
    payload: AigcVideoJobCreateIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if payload.user_id == "anon":
        payload.user_id = user.user_id
    return await AigcVideoService(db).create_job(payload, user)


@router.get("/jobs/{job_id}", response_model=AigcVideoJobOut)
async def get_aigc_video_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await AigcVideoService(db).get_job(job_id, user)


@router.get("/boost-points/{episode_id}", response_model=list[AigcBoostPointOut])
async def list_aigc_boost_points(
    episode_id: str,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
):
    return await AigcVideoService(db).list_boost_points(
        episode_id=episode_id,
        limit=limit,
    )


@router.get("/jobs", response_model=list[AigcVideoJobOut])
async def list_aigc_video_jobs(
    episode_id: str | None = None,
    status: str | None = None,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).list_jobs(
        episode_id=episode_id,
        status=status,
        limit=limit,
    )


@router.post("/boost-points", response_model=AigcBoostPointOut)
async def create_aigc_boost_point(
    payload: AigcBoostPointCreateIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).create_boost_point(payload, user)


@router.get("/boost-points", response_model=list[AigcBoostPointOut])
async def list_admin_aigc_boost_points(
    episode_id: str,
    status: str | None = None,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).list_boost_points(
        episode_id=episode_id,
        include_unpublished=status != "published",
        limit=limit,
    )


@router.post("/jobs/{job_id}/advance", response_model=AigcVideoJobOut)
async def advance_aigc_video_job(
    job_id: str,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).advance_job(job_id)


@router.post("/jobs/{job_id}/approve", response_model=AigcVideoJobOut)
async def approve_aigc_video_job(
    job_id: str,
    payload: AigcVideoReviewIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).review_job(
        job_id,
        approve=True,
        reviewer=user,
        reason=payload.reason,
    )


@router.post("/jobs/{job_id}/reject", response_model=AigcVideoJobOut)
async def reject_aigc_video_job(
    job_id: str,
    payload: AigcVideoReviewIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(require_admin),
):
    return await AigcVideoService(db).review_job(
        job_id,
        approve=False,
        reviewer=user,
        reason=payload.reason,
    )
