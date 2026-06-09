from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import InteractionEffectAsset
from .schemas import InteractionEffectAssetOut, InteractionEffectManifestOut


DEFAULT_EFFECTS = [
    {
        "code": "shuang",
        "label": "爽",
        "actions": ["爽", "打脸爽点", "反杀", "反杀逆袭"],
        "icon": "assets/effects/icons/shuang.svg",
        "animation": {"type": "custom_painter", "preset": "ignition", "duration_ms": 900},
        "sound": {"url": "assets/effects/sounds/shuang_hit.mp3", "volume": 0.8},
        "haptic": "heavy",
        "colors": ["#FF4F72", "#FFC857"],
    },
    {
        "code": "laugh",
        "label": "笑",
        "actions": ["笑", "笑出鹅叫", "搞笑包袱", "离谱"],
        "icon": "assets/effects/icons/laugh.svg",
        "animation": {"type": "custom_painter", "preset": "comedyPop", "duration_ms": 820},
        "sound": {"url": "assets/effects/sounds/laugh_pop.mp3", "volume": 0.72},
        "haptic": "light",
        "colors": ["#52E5C4", "#FFD166"],
    },
    {
        "code": "burn",
        "label": "燃",
        "actions": ["燃", "高能冲突", "护主角", "角色高光"],
        "icon": "assets/effects/icons/burn.svg",
        "animation": {"type": "custom_painter", "preset": "spotlight", "duration_ms": 1100},
        "sound": {"url": "assets/effects/sounds/burn_whoosh.mp3", "volume": 0.76},
        "haptic": "heavy",
        "colors": ["#FF8A3D", "#66E1FF"],
    },
]


class AssetService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get_effect_manifest(self) -> InteractionEffectManifestOut:
        result = await self.db.execute(
            select(InteractionEffectAsset).where(InteractionEffectAsset.enabled == True)  # noqa: E712
        )
        rows = list(result.scalars().all())
        if rows:
            effects = [self._row_to_out(row) for row in rows]
            return InteractionEffectManifestOut(version="db", effects=effects)
        manifest_path = Path(settings.data_root) / "effects" / "manifest.json"
        if manifest_path.exists():
            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
            return InteractionEffectManifestOut.model_validate(payload)
        return InteractionEffectManifestOut(
            version="default",
            effects=[InteractionEffectAssetOut.model_validate(item) for item in DEFAULT_EFFECTS],
        )

    async def seed_defaults(self) -> InteractionEffectManifestOut:
        for item in DEFAULT_EFFECTS:
            existing = await self.db.get(InteractionEffectAsset, item["code"])
            if existing:
                continue
            self.db.add(
                InteractionEffectAsset(
                    code=item["code"],
                    label=item["label"],
                    actions=item["actions"],
                    icon_url=item["icon"],
                    animation_json=item["animation"],
                    sound_url=(item.get("sound") or {}).get("url", ""),
                    haptic=item["haptic"],
                    colors=item["colors"],
                    enabled=True,
                )
            )
        await self.db.commit()
        return await self.get_effect_manifest()

    def _row_to_out(self, row: InteractionEffectAsset) -> InteractionEffectAssetOut:
        sound = {"url": row.sound_url, "volume": 0.8} if row.sound_url else None
        return InteractionEffectAssetOut(
            code=row.code,
            label=row.label,
            actions=row.actions or [],
            icon=row.icon_url,
            animation=row.animation_json or {},
            sound=sound,
            haptic=row.haptic,
            colors=row.colors or [],
        )

