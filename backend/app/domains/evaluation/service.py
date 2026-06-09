from __future__ import annotations

import hashlib
import time

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import Highlight, HighlightEvalItem, HighlightEvalRun, HighlightGoldLabel
from ..security.audit import write_audit_log
from ..security.schemas import CurrentUser
from .metrics import match_highlights
from .schemas import (
    HighlightEvalItemOut,
    HighlightEvalRunCreateIn,
    HighlightEvalRunOut,
    HighlightGoldLabelIn,
    HighlightGoldLabelOut,
)


class EvaluationService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def list_gold_labels(self, episode_id: str) -> list[HighlightGoldLabelOut]:
        result = await self.db.execute(
            select(HighlightGoldLabel)
            .where(HighlightGoldLabel.episode_id == episode_id)
            .order_by(HighlightGoldLabel.ts_start)
        )
        return [HighlightGoldLabelOut.model_validate(item) for item in result.scalars().all()]

    async def create_gold_label(
        self,
        payload: HighlightGoldLabelIn,
        actor: CurrentUser,
    ) -> HighlightGoldLabelOut:
        item = HighlightGoldLabel(**payload.model_dump())
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        await write_audit_log(
            self.db,
            actor=actor,
            action="create_gold_label",
            target_type="highlight_gold_label",
            target_id=str(item.id),
            payload=payload.model_dump(),
        )
        return HighlightGoldLabelOut.model_validate(item)

    async def update_gold_label(
        self,
        label_id: int,
        payload: HighlightGoldLabelIn,
        actor: CurrentUser,
    ) -> HighlightGoldLabelOut:
        item = await self.db.get(HighlightGoldLabel, label_id)
        if item is None:
            raise HTTPException(404, "gold label not found")
        for key, value in payload.model_dump().items():
            setattr(item, key, value)
        await self.db.commit()
        await self.db.refresh(item)
        await write_audit_log(
            self.db,
            actor=actor,
            action="update_gold_label",
            target_type="highlight_gold_label",
            target_id=str(item.id),
            payload=payload.model_dump(),
        )
        return HighlightGoldLabelOut.model_validate(item)

    async def delete_gold_label(self, label_id: int, actor: CurrentUser) -> dict:
        item = await self.db.get(HighlightGoldLabel, label_id)
        if item is None:
            raise HTTPException(404, "gold label not found")
        await self.db.delete(item)
        await self.db.commit()
        await write_audit_log(
            self.db,
            actor=actor,
            action="delete_gold_label",
            target_type="highlight_gold_label",
            target_id=str(label_id),
        )
        return {"deleted": True, "id": label_id}

    async def run(self, payload: HighlightEvalRunCreateIn, actor: CurrentUser) -> HighlightEvalRunOut:
        gold_result = await self.db.execute(
            select(HighlightGoldLabel).where(HighlightGoldLabel.episode_id == payload.episode_id)
        )
        pred_result = await self.db.execute(
            select(Highlight).where(Highlight.episode_id == payload.episode_id)
        )
        gold = list(gold_result.scalars().all())
        pred = list(pred_result.scalars().all())
        if not gold:
            raise HTTPException(400, "gold labels are empty")
        result = match_highlights(gold, pred, iou_threshold=payload.iou_threshold)
        run_id = self._run_id(payload.episode_id)
        run = HighlightEvalRun(
            id=run_id,
            episode_id=payload.episode_id,
            pipeline_version=payload.pipeline_version,
            iou_threshold=payload.iou_threshold,
            precision=result.precision,
            recall=result.recall,
            f1=result.f1,
            type_accuracy=result.type_accuracy,
            true_positive_count=result.tp,
            false_positive_count=result.fp,
            false_negative_count=result.fn,
            raw={"candidate_source": payload.candidate_source},
        )
        self.db.add(run)
        await self.db.flush()
        for match in result.items:
            self.db.add(
                HighlightEvalItem(
                    run_id=run_id,
                    gold_label_id=match.gold_label_id,
                    pred_highlight_id=match.pred_highlight_id,
                    match_type=match.match_type,
                    iou=match.iou,
                    type_match=match.type_match,
                    note=match.note,
                )
            )
        await self.db.commit()
        await self.db.refresh(run)
        await write_audit_log(
            self.db,
            actor=actor,
            action="run_highlight_eval",
            target_type="highlight_eval_run",
            target_id=run_id,
            payload=payload.model_dump(),
        )
        return await self.get_run(run_id)

    async def get_run(self, run_id: str) -> HighlightEvalRunOut:
        run = await self.db.get(HighlightEvalRun, run_id)
        if run is None:
            raise HTTPException(404, "eval run not found")
        item_result = await self.db.execute(
            select(HighlightEvalItem).where(HighlightEvalItem.run_id == run_id)
        )
        items = [
            HighlightEvalItemOut(
                gold_label_id=item.gold_label_id,
                pred_highlight_id=item.pred_highlight_id,
                match_type=item.match_type,
                iou=item.iou,
                type_match=item.type_match,
                note=item.note,
            )
            for item in item_result.scalars().all()
        ]
        return HighlightEvalRunOut(
            run_id=run.id,
            episode_id=run.episode_id,
            pipeline_version=run.pipeline_version,
            iou_threshold=run.iou_threshold,
            precision=run.precision,
            recall=run.recall,
            f1=run.f1,
            type_accuracy=run.type_accuracy,
            true_positive_count=run.true_positive_count,
            false_positive_count=run.false_positive_count,
            false_negative_count=run.false_negative_count,
            created_at=run.created_at,
            items=items,
        )

    async def delete_run(self, run_id: str) -> dict:
        await self.db.execute(delete(HighlightEvalItem).where(HighlightEvalItem.run_id == run_id))
        run = await self.db.get(HighlightEvalRun, run_id)
        if run:
            await self.db.delete(run)
        await self.db.commit()
        return {"deleted": True, "id": run_id}

    def _run_id(self, episode_id: str) -> str:
        digest = hashlib.sha1(f"{episode_id}:{time.time_ns()}".encode("utf-8")).hexdigest()[:10]
        return f"eval_{episode_id}_{digest}"

