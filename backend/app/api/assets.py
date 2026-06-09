from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.assets.schemas import InteractionEffectManifestOut
from ..domains.assets.service import AssetService
from ..domains.security.auth import require_admin
from ..domains.security.schemas import CurrentUser

router = APIRouter(prefix="/api/assets", tags=["assets"])


@router.get("/effects", response_model=InteractionEffectManifestOut)
async def get_effect_manifest(db: AsyncSession = Depends(get_db)):
    return await AssetService(db).get_effect_manifest()


@router.post("/effects/seed", response_model=InteractionEffectManifestOut)
async def seed_effect_manifest(
    db: AsyncSession = Depends(get_db),
    _: CurrentUser = Depends(require_admin),
):
    return await AssetService(db).seed_defaults()

