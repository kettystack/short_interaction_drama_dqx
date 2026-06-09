from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from datetime import datetime, timedelta

from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...database import get_db
from ...models import User
from .schemas import CurrentUser


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _unb64(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def create_access_token(user_id: str, role: str = "viewer") -> str:
    exp = int(
        (
            datetime.utcnow()
            + timedelta(minutes=settings.auth_access_token_ttl_minutes)
        ).timestamp()
    )
    payload = {"sub": user_id, "role": role, "exp": exp}
    body = _b64(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = hmac.new(
        settings.auth_token_secret.encode("utf-8"),
        body.encode("ascii"),
        hashlib.sha256,
    ).digest()
    return f"{body}.{_b64(sig)}"


def decode_access_token(token: str) -> CurrentUser | None:
    try:
        body, sig = token.split(".", 1)
        expected = hmac.new(
            settings.auth_token_secret.encode("utf-8"),
            body.encode("ascii"),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(_unb64(sig), expected):
            return None
        payload = json.loads(_unb64(body))
        if int(payload.get("exp", 0)) < int(time.time()):
            return None
        return CurrentUser(
            user_id=str(payload.get("sub") or "anon"),
            role=str(payload.get("role") or "viewer"),
        )
    except Exception:
        return None


def new_refresh_token() -> str:
    return secrets.token_urlsafe(32)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


async def ensure_user(
    db: AsyncSession,
    user_id: str,
    *,
    display_name: str = "",
    role: str = "viewer",
) -> User:
    user = await db.get(User, user_id)
    if user is None:
        user = User(
            id=user_id,
            display_name=display_name or f"游客{user_id[-4:]}",
            role=role,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    return user


async def get_current_user(
    request: Request,
    authorization: str | None = Header(default=None),
    x_admin_token: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> CurrentUser:
    if x_admin_token and x_admin_token == settings.admin_api_token:
        return CurrentUser(user_id="admin", display_name="Admin", role="admin")

    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        user = decode_access_token(token)
        if user:
            db_user = await db.get(User, user.user_id)
            if db_user:
                user.display_name = db_user.display_name
                user.role = db_user.role
            return user

    user_id = request.headers.get("X-User-Id") or request.query_params.get("user_id") or "anon"
    db_user = await db.get(User, user_id)
    if db_user:
        return CurrentUser(user_id=db_user.id, display_name=db_user.display_name, role=db_user.role)
    return CurrentUser(user_id=user_id)


async def require_admin(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    if not user.is_admin:
        raise HTTPException(403, "admin permission required")
    return user

