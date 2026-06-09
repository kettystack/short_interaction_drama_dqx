from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


PlotEventType = Literal[
    "压迫",
    "反击",
    "身份揭露",
    "打脸",
    "反转",
    "和解",
    "暧昧",
    "悬念",
    "搞笑",
    "铺垫",
]

NarrativeRole = Literal[
    "铺垫",
    "冲突升级",
    "真相揭露",
    "情绪释放",
    "关系变化",
    "剧尾钩子",
]


class RoleRelation(BaseModel):
    target: str
    relation: str


class RoleCard(BaseModel):
    name: str
    aliases: list[str] = Field(default_factory=list)
    traits: list[str] = Field(default_factory=list)
    relationships: list[RoleRelation] = Field(default_factory=list)


class PlotEvent(BaseModel):
    event_id: str
    episode_id: str
    scene_id: str
    ts_start: float
    ts_end: float
    characters: list[str] = Field(default_factory=list)
    event_type: PlotEventType = "铺垫"
    summary: str
    dialogue_evidence: list[str] = Field(default_factory=list)
    visual_evidence: list[str] = Field(default_factory=list)
    narrative_role: NarrativeRole = "铺垫"
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)
    source_signals: list[str] = Field(default_factory=list)


class BranchGenerationIn(BaseModel):
    episode_id: str
    user_id: str = "anon"
    ts_in_video: float = 0.0
    fork_id: int | None = None
    selected_choice: str | None = None
    parent_story_id: str | None = None
    branch_history: list[str] = Field(default_factory=list)
    style: str = "短剧爽感、节奏快、强反转"


class BranchGenerationContext(BaseModel):
    episode_id: str
    current_time: float
    drama_title: str
    episode_title: str
    role_cards: list[RoleCard] = Field(default_factory=list)
    previous_summary: str = ""
    current_scene_events: list[PlotEvent] = Field(default_factory=list)
    recent_events: list[PlotEvent] = Field(default_factory=list)
    selected_choice: str | None = None
    branch_history: list[str] = Field(default_factory=list)
    style: str = "短剧爽感、节奏快、强反转"


class BranchChoiceOut(BaseModel):
    choice_id: str
    label: str
    intent: str = ""
    preview: str = ""


class BranchStoryOut(BaseModel):
    story_id: str
    text: str
    choices: list[BranchChoiceOut] = Field(default_factory=list)
    evidence_event_ids: list[str] = Field(default_factory=list)
    confidence: float = Field(default=0.5, ge=0.0, le=1.0)
    warnings: list[str] = Field(default_factory=list)
