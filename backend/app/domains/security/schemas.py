from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CurrentUser(BaseModel):
    user_id: str = "anon"
    display_name: str = "游客"
    role: str = "viewer"

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"


class AnonymousLoginIn(BaseModel):
    device_id: str = "local-device"
    display_name: str = "游客"


class UserProfileOut(BaseModel):
    id: str
    display_name: str
    role: str
    status: str = "active"


class AuthTokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserProfileOut


class ModerationResult(BaseModel):
    decision: str = "allow"
    risk_score: float = 0.0
    reasons: list[str] = Field(default_factory=list)
    masked_text: str = ""


class ModelCallLogIn(BaseModel):
    provider: str = "doubao"
    model: str = ""
    scene: str
    user_id: str = "system"
    episode_id: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    cost_cents: int = 0
    latency_ms: int = 0
    status: str = "ok"


class AuditLogOut(BaseModel):
    id: int
    actor_id: str
    action: str
    target_type: str
    target_id: str
    created_at: datetime

    class Config:
        from_attributes = True

