from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


StoryTurnRole = Literal["system", "user_choice", "assistant_story"]


class StoryChoiceOut(BaseModel):
    choice_id: str
    label: str
    intent: str = ""
    preview: str = ""
    tone: str = ""


class StoryTurnOut(BaseModel):
    turn_id: str
    thread_id: str
    role: StoryTurnRole
    parent_turn_id: str | None = None
    selected_choice_id: str | None = None
    text: str
    choices: list[StoryChoiceOut] = Field(default_factory=list)
    evidence_event_ids: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class StoryThreadCreateIn(BaseModel):
    episode_id: str
    user_id: str = "anon"
    fork_id: int | None = None
    ts_in_video: float = 0.0
    initial_choice: str | None = None
    context_hint: str = ""
    style_code: str = "cinematic_literary"
    branch_history: list[str] = Field(default_factory=list)


class StoryChoiceIn(BaseModel):
    choice_id: str | None = None
    choice_label: str
    style_code: str | None = None


class StoryMessageIn(BaseModel):
    text: str
    style_code: str | None = None


class StoryThreadOut(BaseModel):
    thread_id: str
    episode_id: str
    user_id: str
    fork_id: int | None = None
    ts_in_video: float
    style_code: str = "cinematic_literary"
    title: str = ""
    turns: list[StoryTurnOut] = Field(default_factory=list)
    branch_path: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class StoryThreadDeltaOut(BaseModel):
    thread_id: str
    appended_turns: list[StoryTurnOut]
    thread: StoryThreadOut

