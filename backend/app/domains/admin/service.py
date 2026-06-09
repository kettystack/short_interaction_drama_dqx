from __future__ import annotations

from datetime import datetime

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import AigcQualityCheck, Branch, BranchFork, ClipAsset, ContentReviewItem, DanmakuItem, Episode, Highlight
from ...schemas import EpisodeOut, HighlightOut
from ..security.audit import write_audit_log
from ..security.schemas import CurrentUser
from .schemas import (
    BranchAdminIn,
    BranchAdminOut,
    BranchForkAdminIn,
    BranchForkAdminOut,
    AigcQualityCheckOut,
    ClipAssetAdminOut,
    HighlightAdminIn,
    ReviewItemOut,
)


class AdminService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def list_episodes(self, limit: int = 200) -> list[EpisodeOut]:
        result = await self.db.execute(
            select(Episode).order_by(Episode.drama_id, Episode.episode_no).limit(min(limit, 500))
        )
        return [EpisodeOut.model_validate(item) for item in result.scalars().all()]

    async def list_highlights(self, episode_id: str) -> list[HighlightOut]:
        result = await self.db.execute(
            select(Highlight).where(Highlight.episode_id == episode_id).order_by(Highlight.ts_start)
        )
        return [HighlightOut.model_validate(item) for item in result.scalars().all()]

    async def create_highlight(self, payload: HighlightAdminIn, actor: CurrentUser) -> HighlightOut:
        item = Highlight(**payload.model_dump())
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        await write_audit_log(
            self.db,
            actor=actor,
            action="create_highlight",
            target_type="highlight",
            target_id=str(item.id),
            payload=payload.model_dump(),
        )
        return HighlightOut.model_validate(item)

    async def update_highlight(self, highlight_id: int, payload: HighlightAdminIn, actor: CurrentUser) -> HighlightOut:
        item = await self.db.get(Highlight, highlight_id)
        if item is None:
            raise HTTPException(404, "highlight not found")
        for key, value in payload.model_dump().items():
            setattr(item, key, value)
        await self.db.commit()
        await self.db.refresh(item)
        await write_audit_log(
            self.db,
            actor=actor,
            action="update_highlight",
            target_type="highlight",
            target_id=str(item.id),
            payload=payload.model_dump(),
        )
        return HighlightOut.model_validate(item)

    async def delete_highlight(self, highlight_id: int, actor: CurrentUser) -> dict:
        item = await self.db.get(Highlight, highlight_id)
        if item is None:
            raise HTTPException(404, "highlight not found")
        await self.db.delete(item)
        await self.db.commit()
        await write_audit_log(
            self.db,
            actor=actor,
            action="delete_highlight",
            target_type="highlight",
            target_id=str(highlight_id),
        )
        return {"deleted": True, "id": highlight_id}

    async def list_forks(self, episode_id: str) -> list[BranchForkAdminOut]:
        result = await self.db.execute(
            select(BranchFork)
            .where(BranchFork.episode_id == episode_id)
            .options(selectinload(BranchFork.branches))
            .order_by(BranchFork.ts_in_video)
        )
        forks = []
        for fork in result.scalars().all():
            fork.branches.sort(key=lambda item: item.order_idx)
            forks.append(self._fork_out(fork))
        return forks

    async def create_fork(self, payload: BranchForkAdminIn, actor: CurrentUser) -> BranchForkAdminOut:
        fork = BranchFork(**payload.model_dump())
        self.db.add(fork)
        await self.db.commit()
        await self.db.refresh(fork)
        await write_audit_log(
            self.db,
            actor=actor,
            action="create_branch_fork",
            target_type="branch_fork",
            target_id=str(fork.id),
            payload=payload.model_dump(),
        )
        return self._fork_out(fork)

    async def update_fork(self, fork_id: int, payload: BranchForkAdminIn, actor: CurrentUser) -> BranchForkAdminOut:
        fork = await self.db.get(BranchFork, fork_id)
        if fork is None:
            raise HTTPException(404, "fork not found")
        for key, value in payload.model_dump().items():
            setattr(fork, key, value)
        await self.db.commit()
        await self.db.refresh(fork)
        await write_audit_log(
            self.db,
            actor=actor,
            action="update_branch_fork",
            target_type="branch_fork",
            target_id=str(fork.id),
            payload=payload.model_dump(),
        )
        return self._fork_out(fork)

    async def delete_fork(self, fork_id: int, actor: CurrentUser) -> dict:
        fork = await self.db.get(BranchFork, fork_id)
        if fork is None:
            raise HTTPException(404, "fork not found")
        await self.db.delete(fork)
        await self.db.commit()
        await write_audit_log(
            self.db,
            actor=actor,
            action="delete_branch_fork",
            target_type="branch_fork",
            target_id=str(fork_id),
        )
        return {"deleted": True, "id": fork_id}

    async def create_branch(self, payload: BranchAdminIn, actor: CurrentUser) -> BranchAdminOut:
        branch = Branch(**payload.model_dump())
        self.db.add(branch)
        await self.db.commit()
        await self.db.refresh(branch)
        await write_audit_log(
            self.db,
            actor=actor,
            action="create_branch",
            target_type="branch",
            target_id=str(branch.id),
            payload=payload.model_dump(),
        )
        return BranchAdminOut.model_validate(branch)

    async def update_branch(self, branch_id: int, payload: BranchAdminIn, actor: CurrentUser) -> BranchAdminOut:
        branch = await self.db.get(Branch, branch_id)
        if branch is None:
            raise HTTPException(404, "branch not found")
        for key, value in payload.model_dump().items():
            setattr(branch, key, value)
        await self.db.commit()
        await self.db.refresh(branch)
        await write_audit_log(
            self.db,
            actor=actor,
            action="update_branch",
            target_type="branch",
            target_id=str(branch.id),
            payload=payload.model_dump(),
        )
        return BranchAdminOut.model_validate(branch)

    async def delete_branch(self, branch_id: int, actor: CurrentUser) -> dict:
        branch = await self.db.get(Branch, branch_id)
        if branch is None:
            raise HTTPException(404, "branch not found")
        await self.db.delete(branch)
        await self.db.commit()
        await write_audit_log(
            self.db,
            actor=actor,
            action="delete_branch",
            target_type="branch",
            target_id=str(branch_id),
        )
        return {"deleted": True, "id": branch_id}

    async def list_reviews(
        self,
        *,
        status: str = "pending",
        item_type: str | None = None,
        limit: int = 100,
    ) -> list[ReviewItemOut]:
        stmt = select(ContentReviewItem)
        if status:
            stmt = stmt.where(ContentReviewItem.status == status)
        if item_type:
            stmt = stmt.where(ContentReviewItem.item_type == item_type)
        result = await self.db.execute(stmt.order_by(ContentReviewItem.created_at.desc()).limit(min(limit, 200)))
        return [ReviewItemOut.model_validate(item) for item in result.scalars().all()]

    async def list_clip_assets(
        self,
        *,
        episode_id: str,
        limit: int = 100,
    ) -> list[ClipAssetAdminOut]:
        result = await self.db.execute(
            select(ClipAsset)
            .where(ClipAsset.episode_id == episode_id)
            .order_by(ClipAsset.ts_start)
            .limit(min(limit, 200))
        )
        return [ClipAssetAdminOut.model_validate(item) for item in result.scalars().all()]

    async def list_aigc_quality_checks(
        self,
        *,
        job_id: str | None = None,
        limit: int = 100,
    ) -> list[AigcQualityCheckOut]:
        stmt = select(AigcQualityCheck)
        if job_id:
            stmt = stmt.where(AigcQualityCheck.job_id == job_id)
        result = await self.db.execute(
            stmt.order_by(AigcQualityCheck.created_at.desc()).limit(min(limit, 200))
        )
        return [AigcQualityCheckOut.model_validate(item) for item in result.scalars().all()]

    async def review_item(self, review_id: int, status: str, reason: str, actor: CurrentUser) -> ReviewItemOut:
        item = await self.db.get(ContentReviewItem, review_id)
        if item is None:
            raise HTTPException(404, "review item not found")
        item.status = status
        item.reason = reason or item.reason
        item.reviewer_id = actor.user_id
        item.reviewed_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(item)
        await write_audit_log(
            self.db,
            actor=actor,
            action=f"review_{status}",
            target_type=item.item_type,
            target_id=item.item_id,
        )
        return ReviewItemOut.model_validate(item)

    async def hide_danmaku(self, danmaku_id: int, reason: str, actor: CurrentUser) -> dict:
        item = await self.db.get(DanmakuItem, danmaku_id)
        if item is None:
            raise HTTPException(404, "danmaku not found")
        item.status = "hidden"
        item.raw = {**(item.raw or {}), "hide_reason": reason, "hidden_by": actor.user_id}
        await self.db.commit()
        await write_audit_log(
            self.db,
            actor=actor,
            action="hide_danmaku",
            target_type="danmaku",
            target_id=str(danmaku_id),
            payload={"reason": reason},
        )
        return {"hidden": True, "id": danmaku_id}

    def _fork_out(self, fork: BranchFork) -> BranchForkAdminOut:
        return BranchForkAdminOut(
            id=fork.id,
            episode_id=fork.episode_id,
            ts_in_video=fork.ts_in_video,
            prompt_text=fork.prompt_text,
            parent_branch_id=fork.parent_branch_id,
            branches=[BranchAdminOut.model_validate(branch) for branch in getattr(fork, "branches", [])],
        )
