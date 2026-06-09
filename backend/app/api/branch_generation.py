from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.narrative.schemas import BranchGenerationIn, BranchStoryOut
from ..domains.narrative.service import BranchGenerationService

router = APIRouter(prefix="/api/branches", tags=["branch-generation"])


@router.post("/generate", response_model=BranchStoryOut)
async def generate_branch_story(
    payload: BranchGenerationIn,
    db: AsyncSession = Depends(get_db),
):
    return await BranchGenerationService(db).generate(payload)
