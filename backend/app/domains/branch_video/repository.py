from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import (
    BranchVideoVariant,
    PersonalizedBranchOption,
    PersonalizedBranchSession,
)


class BranchVideoRepository:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get_session(self, session_id: str) -> PersonalizedBranchSession | None:
        return await self.db.get(PersonalizedBranchSession, session_id)

    async def list_sessions(
        self,
        *,
        episode_id: str,
        user_id: str,
    ) -> list[PersonalizedBranchSession]:
        result = await self.db.execute(
            select(PersonalizedBranchSession)
            .where(
                PersonalizedBranchSession.episode_id == episode_id,
                PersonalizedBranchSession.user_id == user_id,
            )
            .order_by(PersonalizedBranchSession.trigger_ts)
        )
        return list(result.scalars().all())

    async def list_options(self, session_id: str) -> list[PersonalizedBranchOption]:
        result = await self.db.execute(
            select(PersonalizedBranchOption)
            .where(PersonalizedBranchOption.session_id == session_id)
            .order_by(PersonalizedBranchOption.order_idx)
        )
        return list(result.scalars().all())

    async def get_option(self, option_id: str) -> PersonalizedBranchOption | None:
        return await self.db.get(PersonalizedBranchOption, option_id)

    async def latest_variant(self, option_id: str) -> BranchVideoVariant | None:
        result = await self.db.execute(
            select(BranchVideoVariant)
            .where(BranchVideoVariant.option_id == option_id)
            .order_by(BranchVideoVariant.updated_at.desc())
            .limit(1)
        )
        return result.scalars().first()

    async def published_variant(self, option_id: str) -> BranchVideoVariant | None:
        result = await self.db.execute(
            select(BranchVideoVariant)
            .where(
                BranchVideoVariant.option_id == option_id,
                BranchVideoVariant.publish_status == "published",
                BranchVideoVariant.review_status == "approved",
            )
            .order_by(BranchVideoVariant.updated_at.desc())
            .limit(1)
        )
        return result.scalars().first()

    async def variant_by_cache_key(self, cache_key: str) -> BranchVideoVariant | None:
        result = await self.db.execute(
            select(BranchVideoVariant)
            .where(BranchVideoVariant.cache_key == cache_key)
            .limit(1)
        )
        return result.scalars().first()
