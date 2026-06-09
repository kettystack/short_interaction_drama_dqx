from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class HighlightGoldLabelIn(BaseModel):
    episode_id: str
    ts_start: float
    ts_end: float
    type: str
    interaction: str = ""
    description: str = ""
    annotator_id: str = "admin"
    confidence: float = 1.0
    source: str = "manual"


class HighlightGoldLabelOut(HighlightGoldLabelIn):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class HighlightEvalRunCreateIn(BaseModel):
    episode_id: str
    pipeline_version: str = "db_highlights"
    candidate_source: str = "db_highlights"
    iou_threshold: float = 0.3


class HighlightEvalItemOut(BaseModel):
    gold_label_id: int | None = None
    pred_highlight_id: int | None = None
    match_type: str
    iou: float = 0.0
    type_match: bool = False
    note: str = ""


class HighlightEvalRunOut(BaseModel):
    run_id: str
    episode_id: str
    pipeline_version: str
    iou_threshold: float
    precision: float
    recall: float
    f1: float
    type_accuracy: float
    true_positive_count: int
    false_positive_count: int
    false_negative_count: int
    created_at: datetime
    items: list[HighlightEvalItemOut] = Field(default_factory=list)

