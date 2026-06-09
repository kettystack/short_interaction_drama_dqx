from collections import Counter
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import DanmakuItem, DanmakuSetting
from ..schemas import (
    DanmakuIn,
    DanmakuOut,
    DanmakuReportIn,
    DanmakuSettingsIn,
    DanmakuSettingsOut,
    HotWordOut,
)

router = APIRouter(prefix="/api/danmaku", tags=["danmaku"])


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(value, upper))


def _clean_blocked_words(words: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for word in words:
        value = word.strip()[:32]
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
        if len(result) >= 80:
            break
    return result


def _default_settings(user_id: str) -> DanmakuSettingsOut:
    return DanmakuSettingsOut(user_id=user_id, blocked_words=[])


def _settings_to_out(item: DanmakuSetting) -> DanmakuSettingsOut:
    return DanmakuSettingsOut.model_validate(item)


def _apply_settings(item: DanmakuSetting, payload: DanmakuSettingsIn) -> None:
    item.enabled = payload.enabled
    item.display_mode = payload.display_mode if payload.display_mode in {"standard", "compact"} else "standard"
    item.font_size = _clamp(payload.font_size, 10, 48)
    item.opacity = _clamp(payload.opacity, 0.1, 1)
    item.speed = _clamp(payload.speed, 0.5, 2.5)
    item.area = _clamp(payload.area, 0.1, 1)
    item.duration = _clamp(payload.duration, 2, 16)
    item.time_offset = _clamp(payload.time_offset, -60, 60)
    item.show_top = payload.show_top
    item.show_bottom = payload.show_bottom
    item.show_scroll = payload.show_scroll
    item.follow_speed = payload.follow_speed
    item.line_height = _clamp(payload.line_height, 0.8, 3.0)
    item.blocked_words = _clean_blocked_words(payload.blocked_words)
    item.updated_at = datetime.utcnow()


def _density_limit(density: str, limit: int) -> int:
    caps = {"low": 120, "normal": 600, "high": 3000, "all": 60000}
    return min(max(limit, 1), caps.get(density, caps["normal"]))


@router.get("/settings/{user_id}", response_model=DanmakuSettingsOut)
async def get_danmaku_settings(user_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(DanmakuSetting).where(DanmakuSetting.user_id == user_id)
    )
    item = result.scalar_one_or_none()
    if item is None:
        return _default_settings(user_id)
    return _settings_to_out(item)


@router.put("/settings/{user_id}", response_model=DanmakuSettingsOut)
async def save_danmaku_settings(
    user_id: str,
    payload: DanmakuSettingsIn,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(DanmakuSetting).where(DanmakuSetting.user_id == user_id)
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = DanmakuSetting(user_id=user_id)
        db.add(item)
    _apply_settings(item, payload)
    await db.commit()
    await db.refresh(item)
    return _settings_to_out(item)


@router.delete("/settings/{user_id}", response_model=DanmakuSettingsOut)
async def reset_danmaku_settings(user_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(DanmakuSetting).where(DanmakuSetting.user_id == user_id)
    )
    item = result.scalar_one_or_none()
    if item is not None:
        await db.delete(item)
        await db.commit()
    return _default_settings(user_id)


@router.get("/{episode_id}", response_model=list[DanmakuOut])
async def list_danmaku(
    episode_id: str,
    start: float = 0,
    end: float | None = None,
    density: str = "normal",
    limit: int = 300,
    db: AsyncSession = Depends(get_db),
):
    query = select(DanmakuItem).where(
        DanmakuItem.episode_id == episode_id,
        DanmakuItem.status == "visible",
        DanmakuItem.ts_in_video >= start,
    )
    if end is not None:
        query = query.where(DanmakuItem.ts_in_video <= end)
    query = query.order_by(DanmakuItem.ts_in_video, DanmakuItem.like_count.desc()).limit(
        _density_limit(density, limit)
    )
    result = await db.execute(query)
    return result.scalars().all()


@router.post("", response_model=DanmakuOut)
async def post_danmaku(payload: DanmakuIn, db: AsyncSession = Depends(get_db)):
    item = DanmakuItem(
        episode_id=payload.episode_id,
        ts_in_video=max(payload.ts_in_video, 0),
        text=payload.text[:256],
        like_count=max(payload.like_count, 0),
        source="user",
        user_id=payload.user_id,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.post("/{danmaku_id}/report", response_model=DanmakuOut)
async def report_danmaku(danmaku_id: int, payload: DanmakuReportIn, db: AsyncSession = Depends(get_db)):
    item = await db.get(DanmakuItem, danmaku_id)
    if not item:
        raise HTTPException(404, "danmaku not found")
    item.status = "reported"
    raw = dict(item.raw or {})
    raw["report"] = {"user_id": payload.user_id, "reason": payload.reason}
    item.raw = raw
    await db.commit()
    await db.refresh(item)
    return item


@router.get("/{episode_id}/hotwords", response_model=list[HotWordOut])
async def hotwords(episode_id: str, limit: int = 12, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(DanmakuItem.text).where(
            DanmakuItem.episode_id == episode_id,
            DanmakuItem.status == "visible",
        )
    )
    counter = Counter(text for text in result.scalars().all() if text)
    return [HotWordOut(text=text, count=count) for text, count in counter.most_common(max(1, min(limit, 30)))]