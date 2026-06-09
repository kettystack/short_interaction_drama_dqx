from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class BranchVideoContext(BaseModel):
    episode_id: str
    drama_id: str
    episode_title: str
    trigger_source: str
    trigger_ts: float
    resume_at: float
    fork_id: int | None = None
    highlight_id: int | None = None
    highlight_type: str = ""
    highlight_summary: str = ""
    current_conflict: str = ""
    recent_events: list[dict] = Field(default_factory=list)
    active_characters: list[str] = Field(default_factory=list)
    role_cards: list[dict] = Field(default_factory=list)
    previous_summary: str = ""
    source_frame_url: str = ""
    source_frame_path: str = ""
    manual_context: dict = Field(default_factory=dict)
    forbidden_changes: list[str] = Field(default_factory=list)


class BranchOptionPlan(BaseModel):
    option_key: str
    label: str
    description: str
    action: str
    emotion: str
    relationship_change: str = ""
    expected_hook: str = ""
    preview: str = ""


class BranchOptionPlanSet(BaseModel):
    question: str
    options: list[BranchOptionPlan]


class BranchStoryPlan(BaseModel):
    premise: str
    opening_continuity: str
    beats: list[str] = Field(default_factory=list)
    dialogue: list[str] = Field(default_factory=list)
    ending_hook: str
    evidence_event_ids: list[str] = Field(default_factory=list)
    character_constraints: list[str] = Field(default_factory=list)
    negative_constraints: list[str] = Field(default_factory=list)


class BranchShot(BaseModel):
    start: float
    end: float
    framing: str
    action: str
    camera: str


class BranchShotPlan(BaseModel):
    duration: float
    aspect_ratio: str = "9:16"
    source_frame_url: str = ""
    shots: list[BranchShot] = Field(default_factory=list)
    negative_constraints: list[str] = Field(default_factory=list)


class BranchVideoSessionCreateIn(BaseModel):
    episode_id: str
    ts_in_video: float
    fork_id: int | None = None
    highlight_id: int | None = None
    trigger_source: str = "manual"
    option_count: int = Field(default=3, ge=2, le=3)
    target_duration: float = Field(default=12.0, ge=4.0, le=15.0)
    style: str = "竖屏短剧电影感"


class BranchVideoOptionOut(BaseModel):
    id: str
    option_key: str
    label: str
    description: str
    intent: dict = Field(default_factory=dict)
    status: str
    order_idx: int
    story_text: str = ""
    video_url: str = ""
    duration: float = 0.0
    quality_score: float = 0.0
    quality_label: str = ""
    variant_id: str = ""
    error_message: str = ""

    @property
    def is_ready(self) -> bool:
        return self.status == "ready" and bool(self.video_url)


class BranchVideoSessionOut(BaseModel):
    session_id: str
    episode_id: str
    fork_id: int | None = None
    highlight_id: int | None = None
    trigger_source: str
    trigger_ts: float
    resume_at: float
    question: str
    status: str
    options: list[BranchVideoOptionOut] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class BranchVideoPrewarmOut(BaseModel):
    session_id: str
    status: str
    submitted_option_ids: list[str] = Field(default_factory=list)
    session: BranchVideoSessionOut


class BranchVideoCustomOptionIn(BaseModel):
    prompt: str = Field(min_length=2, max_length=500)
    style: str = "竖屏短剧电影感"
    target_duration: float = Field(default=12.0, ge=4.0, le=15.0)


class BranchVideoSelectIn(BaseModel):
    option_id: str
    client_event_id: str = ""


class BranchPlaybackTicket(BaseModel):
    session_id: str
    option_id: str
    variant_id: str
    video_url: str
    duration: float
    main_video_url: str
    resume_at: float
    label: str
    story_text: str = ""


class BranchVideoSelectionOut(BaseModel):
    status: str
    option: BranchVideoOptionOut
    playback_ticket: BranchPlaybackTicket | None = None


class BranchPlaybackEventIn(BaseModel):
    session_id: str
    option_id: str
    variant_id: str
    event_type: str
    ts_in_main_video: float = 0.0
    clip_position: float = 0.0
    client_event_id: str = ""
    payload: dict = Field(default_factory=dict)
