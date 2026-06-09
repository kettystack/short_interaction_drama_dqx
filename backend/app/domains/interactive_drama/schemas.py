from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class InteractiveDramaState(BaseModel):
    reputation: int = 0
    disguise: int = 100
    power: int = 0
    suspicion: int = 0
    romance: int = 0
    justice: int = 0
    heroine: int = 0
    old_friend: int = 0
    emperor: int = 0
    mastermind: int = 0
    route_tags: list[str] = Field(default_factory=list)
    flags: dict[str, bool] = Field(default_factory=dict)


class InteractiveOption(BaseModel):
    option_id: str
    label: str
    description: str = ""
    condition: dict = Field(default_factory=dict)
    state_delta: dict[str, int] = Field(default_factory=dict)
    flags_delta: dict[str, bool] = Field(default_factory=dict)
    route_tags: list[str] = Field(default_factory=list)
    next_node_id: str | None = None
    branch_video_url: str = ""
    branch_start_at: float = 0.0
    branch_duration: float = 0.0
    branch_video_session_hint: str = ""


class InteractiveNode(BaseModel):
    node_id: str
    episode_id: str
    ts_in_video: float = 0.0
    resume_at: float = 0.0
    question: str
    context: str = ""
    options: list[InteractiveOption]
    condition: dict = Field(default_factory=dict)


class InteractiveEnding(BaseModel):
    ending_id: str
    title: str
    summary: str
    category: str = "通关结局"
    condition: dict = Field(default_factory=dict)


class InteractiveGraph(BaseModel):
    drama_id: str
    title: str
    version: str = "interactive-v1"
    initial_node_id: str
    nodes: list[InteractiveNode]
    endings: list[InteractiveEnding] = Field(default_factory=list)


class InteractiveRunCreateIn(BaseModel):
    drama_id: str = "tianxiadyi"
    episode_id: str = "txy_001"
    user_id: str = "anon"
    reset: bool = False


class InteractiveRunOut(BaseModel):
    run_id: str
    drama_id: str
    title: str
    version: str
    user_id: str
    current_episode_id: str
    current_node_id: str | None = None
    state: InteractiveDramaState
    selected_path: list[dict] = Field(default_factory=list)
    active_node: InteractiveNode | None = None
    ending: InteractiveEnding | None = None
    status: str = "active"
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class InteractiveChooseIn(BaseModel):
    node_id: str
    option_id: str
    client_event_id: str = ""


class InteractiveChooseOut(BaseModel):
    run: InteractiveRunOut
    story_text: str
    state_changes: dict[str, int] = Field(default_factory=dict)
    next_node: InteractiveNode | None = None
    ending: InteractiveEnding | None = None
    playback_ticket: dict | None = None
