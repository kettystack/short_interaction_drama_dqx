"""腾讯视频风格频道信息流：短剧竖流与好片榜。"""

from __future__ import annotations

import random

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import Episode
from ..schemas import EpisodeOut, PickFeedItemOut
from .episodes import episode_to_out

router = APIRouter(prefix="/api/feed", tags=["feed"])

DRAMA_META = {
    "beipaixunbao": {
        "genres": ["冒险", "悬疑", "寻宝", "动作"],
        "tagline": "高能寻宝名场面",
    },
    "tianxiadyi": {
        "genres": ["古装", "爽剧", "逆袭", "喜剧"],
        "tagline": "古装逆袭爽点密集",
    },
    "shibasuitainainai": {
        "genres": ["合家欢", "爽剧", "反差", "互动"],
        "tagline": "十八岁太奶奶回场护短，家族反差爽感拉满",
    },
}


async def _episode_list(db: AsyncSession) -> list[Episode]:
    res = await db.execute(
        select(Episode).order_by(Episode.drama_id, Episode.episode_no)
    )
    return list(res.scalars().all())


def _limit(value: int, upper: int = 100) -> int:
    return max(1, min(value, upper))


def _genres_for(episode: Episode) -> list[str]:
    meta = DRAMA_META.get(episode.drama_id, {})
    return list(meta.get("genres", ["短剧", "互动"]))


def _pick_score(episode: Episode, index: int) -> float:
    base = 7.6 + ((episode.episode_no * 7 + index * 3) % 24) / 10
    return round(min(base, 9.9), 1)


@router.get("/shorts", response_model=list[EpisodeOut])
async def shorts_feed(limit: int = 50, db: AsyncSession = Depends(get_db)):
    items = await _episode_list(db)
    random.shuffle(items)
    return [episode_to_out(ep) for ep in items[: _limit(limit)]]


@router.get("/picks", response_model=list[PickFeedItemOut])
async def picks_feed(
    genre: str = "全部",
    limit: int = 30,
    db: AsyncSession = Depends(get_db),
):
    items = await _episode_list(db)
    if genre and genre != "全部":
        items = [ep for ep in items if genre in _genres_for(ep)]

    ranked = sorted(
        enumerate(items),
        key=lambda item: (-_pick_score(item[1], item[0]), item[1].drama_id, item[1].episode_no),
    )
    result: list[PickFeedItemOut] = []
    for index, episode in ranked[: _limit(limit, 50)]:
        genres = _genres_for(episode)
        meta = DRAMA_META.get(episode.drama_id, {})
        result.append(
            PickFeedItemOut(
                episode=episode_to_out(episode),
                score=_pick_score(episode, index),
                reason=str(meta.get("tagline", "AI 互动高能短剧")),
                tags=genres[:3],
            )
        )
    return result
