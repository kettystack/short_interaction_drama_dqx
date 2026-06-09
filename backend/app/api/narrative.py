from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.narrative.context_builder import NarrativeContextBuilder
from ..domains.narrative.repository import NarrativeRepository
from ..domains.narrative.schemas import BranchGenerationContext, BranchGenerationIn, PlotEvent

router = APIRouter(prefix="/api/narrative", tags=["narrative"])


@router.get("/events/{episode_id}", response_model=list[PlotEvent])
async def list_plot_events(episode_id: str):
    return NarrativeRepository().load_events(episode_id)


@router.get("/context/preview", response_model=BranchGenerationContext)
async def preview_generation_context(
    episode_id: str,
    ts_in_video: float = Query(0.0, ge=0.0),
    selected_choice: str | None = None,
    branch_history: str = "",
    style: str = "短剧爽感、节奏快、强反转",
    db: AsyncSession = Depends(get_db),
):
    payload = BranchGenerationIn(
        episode_id=episode_id,
        ts_in_video=ts_in_video,
        selected_choice=selected_choice,
        branch_history=[item.strip() for item in branch_history.split(",") if item.strip()],
        style=style,
    )
    return await NarrativeContextBuilder(db).build(payload)
