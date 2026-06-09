from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import PlaybackEvent
from ..schemas import PlaybackEventIn, PlaybackEventOut

router = APIRouter(prefix="/api/analytics", tags=["analytics"])


@router.post("/playback", response_model=PlaybackEventOut)
async def post_playback_event(payload: PlaybackEventIn, db: AsyncSession = Depends(get_db)):
    event = PlaybackEvent(
        user_id=payload.user_id,
        episode_id=payload.episode_id,
        event_type=payload.event_type,
        ts_in_video=max(payload.ts_in_video, 0),
        duration=max(payload.duration, 0),
        payload_json=payload.payload,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return event