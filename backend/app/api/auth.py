from __future__ import annotations

import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import get_db
from ..domains.security.auth import (
    create_access_token,
    ensure_user,
    get_current_user,
    hash_refresh_token,
    new_refresh_token,
)
from ..domains.security.schemas import AnonymousLoginIn, AuthTokenOut, CurrentUser, UserProfileOut
from ..models import DeviceSession

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/anonymous-login", response_model=AuthTokenOut)
async def anonymous_login(payload: AnonymousLoginIn, db: AsyncSession = Depends(get_db)):
    suffix = secrets.token_hex(4)
    user_id = f"u_{suffix}"
    user = await ensure_user(db, user_id, display_name=payload.display_name or f"游客{suffix}")
    refresh_token = new_refresh_token()
    session = DeviceSession(
        id=f"s_{secrets.token_hex(8)}",
        user_id=user.id,
        device_id=payload.device_id,
        refresh_token_hash=hash_refresh_token(refresh_token),
        expires_at=datetime.utcnow() + timedelta(days=30),
    )
    db.add(session)
    await db.commit()
    return AuthTokenOut(
        access_token=create_access_token(user.id, user.role),
        refresh_token=refresh_token,
        user=UserProfileOut(id=user.id, display_name=user.display_name, role=user.role, status=user.status),
    )


@router.get("/me", response_model=UserProfileOut)
async def me(user: CurrentUser = Depends(get_current_user)):
    return UserProfileOut(
        id=user.user_id,
        display_name=user.display_name,
        role=user.role,
        status="active",
    )

