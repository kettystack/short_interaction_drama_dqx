from __future__ import annotations

import hashlib
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import RateLimitBucket
from .schemas import CurrentUser


async def check_rate_limit(
    db: AsyncSession,
    user: CurrentUser,
    route_group: str,
    *,
    limit: int,
    window_seconds: int,
) -> None:
    if not settings.rate_limit_enabled or user.is_admin:
        return
    now = datetime.utcnow()
    window_start = now.replace(microsecond=0)
    bucket_key = f"{user.user_id}:{route_group}:{int(now.timestamp()) // window_seconds}"
    bucket_id = hashlib.sha1(bucket_key.encode("utf-8")).hexdigest()
    bucket = await db.get(RateLimitBucket, bucket_id)
    if bucket is None:
        bucket = RateLimitBucket(
            id=bucket_id,
            user_id=user.user_id,
            route_group=route_group,
            window_start=window_start,
            count=1,
            expires_at=now + timedelta(seconds=window_seconds * 2),
        )
        db.add(bucket)
        await db.commit()
        return
    if bucket.count >= limit:
        raise HTTPException(429, f"rate limit exceeded: {route_group}")
    bucket.count += 1
    await db.commit()

