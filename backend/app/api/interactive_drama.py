from __future__ import annotations

from fastapi import APIRouter

from ..domains.interactive_drama.schemas import (
    InteractiveChooseIn,
    InteractiveChooseOut,
    InteractiveRunCreateIn,
    InteractiveRunOut,
)
from ..domains.interactive_drama.service import InteractiveDramaService

router = APIRouter(prefix="/api/interactive-drama", tags=["interactive-drama"])


@router.post("/runs", response_model=InteractiveRunOut)
async def start_interactive_run(payload: InteractiveRunCreateIn):
    return await InteractiveDramaService().start_run(payload)


@router.get("/runs/{run_id}", response_model=InteractiveRunOut)
async def get_interactive_run(run_id: str):
    return await InteractiveDramaService().get_run(run_id)


@router.post("/runs/{run_id}/choose", response_model=InteractiveChooseOut)
async def choose_interactive_option(run_id: str, payload: InteractiveChooseIn):
    return await InteractiveDramaService().choose(run_id, payload)


@router.post("/runs/{run_id}/reset", response_model=InteractiveRunOut)
async def reset_interactive_run(run_id: str):
    return await InteractiveDramaService().reset_run(run_id)


@router.post("/runs/{run_id}/rewind", response_model=InteractiveRunOut)
async def rewind_interactive_run(run_id: str):
    return await InteractiveDramaService().rewind_run(run_id)
