from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class InteractionIn(BaseModel):
    episode_id: str
    highlight_id: int | None = None
    action: str
    ts_in_video: float
    user_id: str = "anon"
    effect: str | None = None
    client_event_id: str | None = Field(default=None, max_length=128)
    payload: dict[str, Any] = Field(default_factory=dict)


class InteractionOut(BaseModel):
    id: int
    event_id: str
    client_event_id: str | None = None
    episode_id: str
    highlight_id: int | None = None
    action: str
    effect: str | None = None
    ts_in_video: float
    user_id: str
    server_ts: datetime
    created_at: datetime
    count: int
    display_count: int
    payload: dict[str, Any] = Field(default_factory=dict)


class InteractionSummaryOut(BaseModel):
    episode_id: str
    action: str
    count: int
    display_count: int
    label: str


class InteractionTimelineBucketOut(BaseModel):
    episode_id: str
    bucket_start: float
    bucket_size: int
    action: str
    effect: str | None = None
    count: int
    display_count: int


class StoryFeedbackOut(BaseModel):
    """AI 续写 / 高光卡 的点赞、评论摘要。"""
    episode_id: str
    likes: int
    comments: list[dict[str, Any]] = Field(default_factory=list)
