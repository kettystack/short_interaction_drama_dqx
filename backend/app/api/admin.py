from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.admin.schemas import (
    AigcQualityCheckOut,
    BranchAdminIn,
    BranchAdminOut,
    BranchForkAdminIn,
    BranchForkAdminOut,
    ClipAssetAdminOut,
    HighlightAdminIn,
    ReviewDecisionIn,
    ReviewItemOut,
)
from ..domains.admin.service import AdminService
from ..domains.security.auth import require_admin
from ..domains.security.schemas import CurrentUser
from ..schemas import EpisodeOut, HighlightOut

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.get("/episodes", response_model=list[EpisodeOut])
async def list_admin_episodes(
    limit: int = 200,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_episodes(limit)


@router.get("/highlights", response_model=list[HighlightOut])
async def list_admin_highlights(
    episode_id: str,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_highlights(episode_id)


@router.post("/highlights", response_model=HighlightOut)
async def create_admin_highlight(
    payload: HighlightAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).create_highlight(payload, actor)


@router.put("/highlights/{highlight_id}", response_model=HighlightOut)
async def update_admin_highlight(
    highlight_id: int,
    payload: HighlightAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).update_highlight(highlight_id, payload, actor)


@router.delete("/highlights/{highlight_id}")
async def delete_admin_highlight(
    highlight_id: int,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).delete_highlight(highlight_id, actor)


@router.get("/branches/forks", response_model=list[BranchForkAdminOut])
async def list_admin_forks(
    episode_id: str,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_forks(episode_id)


@router.post("/branches/forks", response_model=BranchForkAdminOut)
async def create_admin_fork(
    payload: BranchForkAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).create_fork(payload, actor)


@router.put("/branches/forks/{fork_id}", response_model=BranchForkAdminOut)
async def update_admin_fork(
    fork_id: int,
    payload: BranchForkAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).update_fork(fork_id, payload, actor)


@router.delete("/branches/forks/{fork_id}")
async def delete_admin_fork(
    fork_id: int,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).delete_fork(fork_id, actor)


@router.post("/branches", response_model=BranchAdminOut)
async def create_admin_branch(
    payload: BranchAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).create_branch(payload, actor)


@router.put("/branches/{branch_id}", response_model=BranchAdminOut)
async def update_admin_branch(
    branch_id: int,
    payload: BranchAdminIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).update_branch(branch_id, payload, actor)


@router.delete("/branches/{branch_id}")
async def delete_admin_branch(
    branch_id: int,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).delete_branch(branch_id, actor)


@router.get("/reviews", response_model=list[ReviewItemOut])
async def list_reviews(
    status: str = "pending",
    item_type: str | None = None,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_reviews(status=status, item_type=item_type, limit=limit)


@router.get("/clip-assets", response_model=list[ClipAssetAdminOut])
async def list_clip_assets(
    episode_id: str,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_clip_assets(episode_id=episode_id, limit=limit)


@router.get("/aigc-quality-checks", response_model=list[AigcQualityCheckOut])
async def list_aigc_quality_checks(
    job_id: str | None = None,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).list_aigc_quality_checks(job_id=job_id, limit=limit)


@router.post("/reviews/{review_id}/approve", response_model=ReviewItemOut)
async def approve_review(
    review_id: int,
    payload: ReviewDecisionIn = ReviewDecisionIn(),
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).review_item(review_id, "approved", payload.reason, actor)


@router.post("/reviews/{review_id}/reject", response_model=ReviewItemOut)
async def reject_review(
    review_id: int,
    payload: ReviewDecisionIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).review_item(review_id, "rejected", payload.reason, actor)


@router.post("/danmaku/{danmaku_id}/hide")
async def hide_danmaku(
    danmaku_id: int,
    payload: ReviewDecisionIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await AdminService(db).hide_danmaku(danmaku_id, payload.reason, actor)
