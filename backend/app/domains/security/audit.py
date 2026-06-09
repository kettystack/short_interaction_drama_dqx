from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from ...models import AuditLog
from .schemas import CurrentUser


async def write_audit_log(
    db: AsyncSession,
    *,
    actor: CurrentUser,
    action: str,
    target_type: str,
    target_id: str = "",
    payload: dict | None = None,
) -> None:
    db.add(
        AuditLog(
            actor_id=actor.user_id,
            action=action,
            target_type=target_type,
            target_id=str(target_id),
            payload_json=payload or {},
        )
    )
    await db.commit()

