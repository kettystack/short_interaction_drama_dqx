from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.story_chat.schemas import (
    StoryChoiceIn,
    StoryMessageIn,
    StoryThreadCreateIn,
    StoryThreadDeltaOut,
    StoryThreadOut,
)
from ..domains.story_chat.service import StoryChatService

router = APIRouter(prefix="/api/story-chat", tags=["story-chat"])


@router.post("/threads", response_model=StoryThreadOut)
async def create_story_thread(
    payload: StoryThreadCreateIn,
    db: AsyncSession = Depends(get_db),
):
    return await StoryChatService(db).create_thread(payload)


@router.get("/threads/{thread_id}", response_model=StoryThreadOut)
async def get_story_thread(
    thread_id: str,
    db: AsyncSession = Depends(get_db),
):
    return await StoryChatService(db).get_thread(thread_id)


@router.get("/users/{user_id}/threads", response_model=list[StoryThreadOut])
async def list_user_story_threads(
    user_id: str,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
):
    return await StoryChatService(db).list_user_threads(user_id, limit=limit)


@router.post("/threads/{thread_id}/choose", response_model=StoryThreadDeltaOut)
async def choose_story_branch(
    thread_id: str,
    payload: StoryChoiceIn,
    db: AsyncSession = Depends(get_db),
):
    return await StoryChatService(db).choose(thread_id, payload)


@router.post("/threads/{thread_id}/message", response_model=StoryThreadDeltaOut)
async def send_story_message(
    thread_id: str,
    payload: StoryMessageIn,
    db: AsyncSession = Depends(get_db),
):
    return await StoryChatService(db).message(thread_id, payload)
