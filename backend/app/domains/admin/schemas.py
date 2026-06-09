from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from ...schemas import HighlightOut


class HighlightAdminIn(BaseModel):
    episode_id: str
    ts_start: float
    ts_end: float
    type: str
    interaction: str
    intensity: float = 0.6
    description: str = ""
    raw: dict = Field(default_factory=dict)


class BranchForkAdminIn(BaseModel):
    episode_id: str
    ts_in_video: float
    prompt_text: str = "接下来怎么走？"
    parent_branch_id: int | None = None


class BranchAdminIn(BaseModel):
    fork_id: int
    choice_label: str
    video_url: str = ""
    duration: float = 0.0
    order_idx: int = 0
    description: str = ""
    next_fork_id: int | None = None


class BranchAdminOut(BaseModel):
    id: int
    fork_id: int
    choice_label: str
    video_url: str
    duration: float
    order_idx: int
    description: str
    next_fork_id: int | None = None

    class Config:
        from_attributes = True


class BranchForkAdminOut(BaseModel):
    id: int
    episode_id: str
    ts_in_video: float
    prompt_text: str
    parent_branch_id: int | None = None
    branches: list[BranchAdminOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class ReviewItemOut(BaseModel):
    id: int
    item_type: str
    item_id: str
    episode_id: str
    user_id: str
    text: str
    status: str
    risk_score: float
    reason: str
    reviewer_id: str
    reviewed_at: datetime | None = None
    created_at: datetime

    class Config:
        from_attributes = True


class ReviewDecisionIn(BaseModel):
    reason: str = ""


class ClipAssetAdminOut(BaseModel):
    id: str
    drama_id: str
    episode_id: str
    source_video_url: str
    clip_url: str
    ts_start: float
    ts_end: float
    duration: float
    action_tags: list[str] = Field(default_factory=list)
    emotion_tags: list[str] = Field(default_factory=list)
    visual_tags: list[str] = Field(default_factory=list)
    transcript: str
    source: str
    status: str
    quality_score: float

    class Config:
        from_attributes = True


class AigcQualityCheckOut(BaseModel):
    id: int
    job_id: str
    candidate_url: str
    context_score: float
    character_score: float
    action_score: float
    style_score: float
    final_score: float
    final_decision: str
    reasons: list[str] = Field(default_factory=list)
    created_at: datetime

    class Config:
        from_attributes = True
