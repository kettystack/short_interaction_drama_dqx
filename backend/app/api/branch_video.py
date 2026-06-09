from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.branch_video.schemas import (
    BranchPlaybackEventIn,
    BranchVideoCustomOptionIn,
    BranchVideoPrewarmOut,
    BranchVideoSelectionOut,
    BranchVideoSelectIn,
    BranchVideoSessionCreateIn,
    BranchVideoSessionOut,
)
from ..domains.branch_video.service import BranchVideoService
from ..domains.security.auth import get_current_user
from ..domains.security.schemas import CurrentUser

router = APIRouter(prefix="/api/branch-video", tags=["branch-video"])


@router.get(
    "/episodes/{episode_id}/sessions",
    response_model=list[BranchVideoSessionOut],
)
async def list_episode_branch_video_sessions(
    episode_id: str,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).ensure_episode_sessions(
        episode_id=episode_id,
        user=user,
    )


@router.post("/sessions", response_model=BranchVideoSessionOut)
async def create_branch_video_session(
    payload: BranchVideoSessionCreateIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).create_session(payload, user=user)


@router.get("/sessions/{session_id}", response_model=BranchVideoSessionOut)
async def get_branch_video_session(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).get_session(session_id, user=user)


@router.post(
    "/sessions/{session_id}/prewarm",
    response_model=BranchVideoPrewarmOut,
)
async def prewarm_branch_video_session(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).prewarm(session_id, user=user)


@router.post(
    "/sessions/{session_id}/custom-options",
    response_model=BranchVideoSessionOut,
)
async def create_custom_branch_video_option(
    session_id: str,
    payload: BranchVideoCustomOptionIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).create_custom_option(
        session_id,
        payload,
        user=user,
    )


@router.post(
    "/sessions/{session_id}/select",
    response_model=BranchVideoSelectionOut,
)
async def select_branch_video_option(
    session_id: str,
    payload: BranchVideoSelectIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).select_option(
        session_id,
        payload,
        user=user,
    )


@router.post("/events")
async def record_branch_video_event(
    payload: BranchPlaybackEventIn,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    return await BranchVideoService(db).record_event(payload, user=user)
