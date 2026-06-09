import json
import math
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import get_db
from ..models import Episode, Highlight
from ..schemas import HighlightOut

router = APIRouter(prefix="/api/highlights", tags=["highlights"])


INTERACTION_MAP = {
    "家族冲突": "燃",
    "护短撑腰": "护主角",
    "身份反转": "炸裂",
    "年龄反差梗": "离谱",
    "打脸爽点": "爽",
    "反杀逆袭": "爽",
    "高能冲突": "燃",
    "反派压迫": "屏息",
    "搞笑包袱": "笑",
    "离谱吐槽": "离谱",
    "颜值名场面": "封神",
    "CP磕糖": "磕",
    "泪点破防": "破防",
    "治愈和解": "治愈",
    "剧情悬念": "炸裂",
    "上头追更": "上头",
    "角色高光": "燃",
    "名台词": "封神",
}
TYPE_ALIASES = {
    "冲突": "高能冲突",
    "悬念": "剧情悬念",
    "搞笑": "搞笑包袱",
    "爽点": "打脸爽点",
    "打脸": "打脸爽点",
    "反杀": "反杀逆袭",
    "反转": "身份反转",
    "名场面": "角色高光",
    "虐心": "泪点破防",
    "甜蜜": "CP磕糖",
    "高甜": "CP磕糖",
    "磕糖": "CP磕糖",
    "破防": "泪点破防",
    "紧张": "反派压迫",
}
INTERACTION_CHOICES = set(INTERACTION_MAP.values())


def _normalize_type(value: object) -> str:
    htype = str(value or "角色高光").strip()
    return TYPE_ALIASES.get(htype, htype)


def _normalize_interaction(value: object, htype: str) -> str:
    interaction = str(value or "").strip()
    if interaction in INTERACTION_CHOICES:
        return interaction
    return INTERACTION_MAP.get(htype, "爽")


def _round_time(value: float, *, duration: float = 0.0) -> float:
    if duration > 0 and value >= duration:
        return math.floor(duration * 100) / 100
    return round(value, 2)


def _sanitize_highlight(item: dict, *, duration: float) -> dict | None:
    try:
        ts_start = max(0.0, float(item["ts_start"]))
        ts_end = max(0.0, float(item["ts_end"]))
    except (KeyError, TypeError, ValueError):
        return None
    if duration > 0:
        if ts_start >= duration:
            return None
        ts_end = min(ts_end, duration)
    if ts_end <= ts_start:
        return None
    htype = _normalize_type(item.get("type"))
    raw = dict(item)
    interaction = _normalize_interaction(item.get("interaction"), htype)
    raw["normalized_type"] = htype
    raw["normalized_interaction"] = interaction
    return {
        "ts_start": round(ts_start, 2),
        "ts_end": _round_time(ts_end, duration=duration),
        "type": htype,
        "interaction": interaction,
        "intensity": max(0.0, min(1.0, float(item.get("intensity", 0.6)))),
        "description": str(item.get("description") or "")[:120],
        "raw": raw,
    }


@router.get("/{episode_id}", response_model=list[HighlightOut])
async def list_highlights(episode_id: str, db: AsyncSession = Depends(get_db)):
    res = await db.execute(
        select(Highlight).where(Highlight.episode_id == episode_id).order_by(Highlight.ts_start)
    )
    return res.scalars().all()


@router.post("/import/{episode_id}")
async def import_highlights(episode_id: str, db: AsyncSession = Depends(get_db)):
    """从 data/highlights/{episode_id}.json 导入 AI Pipeline 产出。"""
    ep = await db.get(Episode, episode_id)
    if not ep:
        raise HTTPException(404, "episode not exists, create it first")

    path = Path(settings.data_root) / "highlights" / f"{episode_id}.json"
    if not path.exists():
        raise HTTPException(404, f"no highlight file: {path}")

    payload = json.loads(path.read_text(encoding="utf-8"))
    duration = float(ep.duration or payload.get("duration") or 0.0)
    # 先清空旧的
    await db.execute(
        Highlight.__table__.delete().where(Highlight.episode_id == episode_id)
    )
    count = 0
    for h in payload.get("highlights", []):
        normalized = _sanitize_highlight(h, duration=duration)
        if normalized is None:
            continue
        db.add(
            Highlight(
                episode_id=episode_id,
                ts_start=normalized["ts_start"],
                ts_end=normalized["ts_end"],
                type=normalized["type"],
                interaction=normalized["interaction"],
                intensity=normalized["intensity"],
                description=normalized["description"],
                raw=normalized["raw"],
            )
        )
        count += 1
    await db.commit()
    return {"imported": count}
