from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.evaluation.schemas import (
    HighlightEvalRunCreateIn,
    HighlightEvalRunOut,
    HighlightGoldLabelIn,
    HighlightGoldLabelOut,
)
from ..domains.evaluation.service import EvaluationService
from ..domains.security.auth import require_admin
from ..domains.security.schemas import CurrentUser

router = APIRouter(prefix="/api/evaluation", tags=["evaluation"])


@router.get("/gold-labels/{episode_id}", response_model=list[HighlightGoldLabelOut])
async def list_gold_labels(
    episode_id: str,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).list_gold_labels(episode_id)


@router.post("/gold-labels", response_model=HighlightGoldLabelOut)
async def create_gold_label(
    payload: HighlightGoldLabelIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).create_gold_label(payload, actor)


@router.put("/gold-labels/{label_id}", response_model=HighlightGoldLabelOut)
async def update_gold_label(
    label_id: int,
    payload: HighlightGoldLabelIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).update_gold_label(label_id, payload, actor)


@router.delete("/gold-labels/{label_id}")
async def delete_gold_label(
    label_id: int,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).delete_gold_label(label_id, actor)


@router.post("/runs", response_model=HighlightEvalRunOut)
async def run_evaluation(
    payload: HighlightEvalRunCreateIn,
    db: AsyncSession = Depends(get_db),
    actor: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).run(payload, actor)


@router.get("/runs/{run_id}", response_model=HighlightEvalRunOut)
async def get_evaluation_run(
    run_id: str,
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await EvaluationService(db).get_run(run_id)

