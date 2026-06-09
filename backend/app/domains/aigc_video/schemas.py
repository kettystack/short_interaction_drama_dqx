from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class AigcVideoJobCreateIn(BaseModel):
    episode_id: str
    user_id: str = "anon"
    ts_in_video: float = 0.0
    trigger_type: str = "boost"
    user_prompt: str = ""
    style_code: str = "short_drama_punchy"
    highlight_id: int | None = None
    story_thread_id: str | None = None
    idempotency_key: str | None = None
    duration_seconds: float | None = Field(default=None, ge=2.0, le=15.0)


class AigcVideoJobOut(BaseModel):
    job_id: str
    episode_id: str
    user_id: str
    status: str
    progress: float
    trigger_type: str
    prompt: str
    provider: str
    provider_job_id: str | None = None
    output_video_url: str = ""
    hls_url: str = ""
    cover_url: str = ""
    duration: float = 0.0
    resume_at: float = 0.0
    insert_mode: str = "pause_main_then_play_clip"
    error_message: str = ""
    quality_score: float = 0.0
    quality_decision: str = ""
    status_history: list[dict] = Field(default_factory=list)
    review_frames: list[str] = Field(default_factory=list)
    poll_url: str = ""
    created_at: datetime
    updated_at: datetime


class AigcBoostPointCreateIn(BaseModel):
    episode_id: str
    trigger_ts: float
    resume_at: float | None = None
    title: str = "加速包"
    prompt: str = ""
    source_job_id: str | None = None
    output_video_url: str = ""
    hls_url: str = ""
    cover_url: str = ""
    duration: float = 0.0
    quality_score: float = 0.0
    provider: str = ""
    status: str = "published"
    raw: dict = Field(default_factory=dict)


class AigcBoostPointOut(BaseModel):
    id: str
    episode_id: str
    trigger_ts: float
    resume_at: float
    title: str
    prompt: str = ""
    provider: str = ""
    source_job_id: str = ""
    output_video_url: str = ""
    hls_url: str = ""
    cover_url: str = ""
    duration: float = 0.0
    quality_score: float = 0.0
    status: str = "published"
    created_at: datetime
    updated_at: datetime


class ProviderJob(BaseModel):
    provider_job_id: str
    status: str = "submitted"
    progress: float = 0.0
    output_video_url: str = ""
    duration: float = 0.0
    cover_url: str = ""


class ProviderJobStatus(BaseModel):
    provider_job_id: str
    status: str
    progress: float = 0.0
    output_video_url: str = ""
    duration: float = 0.0
    cover_url: str = ""


class VideoGenerationRequest(BaseModel):
    job_id: str
    episode_id: str
    prompt: str
    trigger_type: str
    style_code: str = "short_drama_punchy"
    source_context: dict = Field(default_factory=dict)
    first_frame_url: str = ""
    last_frame_url: str = ""
    first_frame_path: str = ""
    last_frame_path: str = ""
    generation_mode: str = "first_frame_to_video"
    duration: float = 5.0
    ratio: str = "9:16"


class AigcGenerationContext(BaseModel):
    episode_id: str
    drama_id: str
    episode_title: str
    ts_in_video: float
    resume_at: float
    trigger_type: str
    highlight_id: int | None = None
    highlight_text: str = ""
    nearby_highlights: list[dict] = Field(default_factory=list)
    nearby_events: list[dict] = Field(default_factory=list)
    branch_path: list[str] = Field(default_factory=list)
    story_thread_id: str | None = None
    first_frame_url: str = ""
    last_frame_url: str = ""
    first_frame_path: str = ""
    last_frame_path: str = ""


class VideoInsertIntent(BaseModel):
    trigger_type: str
    action: str
    emotion: str
    camera_style: str = "竖屏短剧，强节奏，镜头稳定"
    duration_seconds: float = 5.0
    must_include: list[str] = Field(default_factory=list)
    must_avoid: list[str] = Field(default_factory=list)
    prompt: str


class ClipCandidate(BaseModel):
    clip_id: str
    clip_url: str
    episode_id: str
    drama_id: str = ""
    ts_start: float = 0.0
    ts_end: float = 0.0
    duration: float = 0.0
    score: float = 0.0
    source: str = "clip_asset"
    provider: str = "asset_resolver"
    match_reasons: list[str] = Field(default_factory=list)


class QualityGateResult(BaseModel):
    decision: str
    score: float
    context_score: float = 0.0
    character_score: float = 0.0
    action_score: float = 0.0
    style_score: float = 0.0
    safety_score: float = 0.0
    technical_score: float = 0.0
    multimodal_score: float = 0.0
    requires_human_review: bool = False
    reasons: list[str] = Field(default_factory=list)
    raw: dict = Field(default_factory=dict)


class MultimodalQualityResult(BaseModel):
    available: bool = False
    decision: str = "review"
    character_continuity: float = 0.0
    scene_continuity: float = 0.0
    action_match: float = 0.0
    visual_quality: float = 0.0
    safety_score: float = 0.0
    copyright_risk: float = 0.0
    obvious_mismatch: bool = False
    reasons: list[str] = Field(default_factory=list)
    raw: dict = Field(default_factory=dict)


class AigcVideoReviewIn(BaseModel):
    reason: str = ""
