from __future__ import annotations

import hashlib
import logging
import time
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import Episode
from ..security.cost_tracker import tracked_chat_completion
from ..narrative.context_builder import NarrativeContextBuilder
from ..narrative.schemas import BranchGenerationIn
from .db_repository import StoryChatDbRepository
from .prompt_builder import build_story_chat_messages
from .quality_guard import fallback_assistant_turn, parse_assistant_turn
from .schemas import (
    StoryChoiceIn,
    StoryMessageIn,
    StoryThreadCreateIn,
    StoryThreadDeltaOut,
    StoryThreadOut,
    StoryTurnOut,
)
from .style_profiles import get_style_profile


logger = logging.getLogger(__name__)


class StoryChatService:
    def __init__(self, db: AsyncSession, repository: StoryChatDbRepository | None = None):
        self.db = db
        self.repository = repository or StoryChatDbRepository(db)

    async def create_thread(self, payload: StoryThreadCreateIn) -> StoryThreadOut:
        episode = await self.db.get(Episode, payload.episode_id)
        if episode is None:
            raise HTTPException(404, f"episode not exists: {payload.episode_id}")

        now = datetime.utcnow()
        thread = StoryThreadOut(
            thread_id=self._thread_id(payload),
            episode_id=payload.episode_id,
            user_id=payload.user_id,
            fork_id=payload.fork_id,
            ts_in_video=payload.ts_in_video,
            style_code=get_style_profile(payload.style_code).code,
            title=episode.title,
            branch_path=list(payload.branch_history),
            created_at=now,
            updated_at=now,
        )
        appended: list[StoryTurnOut] = []
        action_text = (payload.initial_choice or "继续本集剧情").strip()
        user_turn = self._user_turn(thread, action_text)
        appended.append(user_turn)
        if payload.initial_choice:
            thread.branch_path.append(payload.initial_choice)
        assistant_turn = await self._generate_assistant_turn(
            thread,
            action_text=action_text,
            context_hint=payload.context_hint,
            parent_turn_id=user_turn.turn_id,
        )
        appended.append(assistant_turn)
        thread.updated_at = datetime.utcnow()
        thread.turns.extend(appended)
        return await self.repository.save_thread(thread)

    async def get_thread(self, thread_id: str) -> StoryThreadOut:
        thread = await self.repository.get_thread(thread_id)
        if thread is None:
            raise HTTPException(404, f"thread not exists: {thread_id}")
        return thread

    async def list_user_threads(self, user_id: str, limit: int = 50) -> list[StoryThreadOut]:
        return await self.repository.list_user_threads(user_id, limit=limit)

    async def choose(self, thread_id: str, payload: StoryChoiceIn) -> StoryThreadDeltaOut:
        thread = await self.get_thread(thread_id)
        if payload.style_code:
            thread.style_code = get_style_profile(payload.style_code).code
        user_turn = self._user_turn(
            thread,
            payload.choice_label,
            selected_choice_id=payload.choice_id,
        )
        thread.branch_path.append(payload.choice_label)
        thread.turns.append(user_turn)
        assistant_turn = await self._generate_assistant_turn(
            thread,
            action_text=payload.choice_label,
            context_hint="",
            parent_turn_id=user_turn.turn_id,
        )
        thread.turns.append(assistant_turn)
        thread.updated_at = datetime.utcnow()
        await self.repository.save_thread(thread)
        return StoryThreadDeltaOut(
            thread_id=thread.thread_id,
            appended_turns=[user_turn, assistant_turn],
            thread=thread,
        )

    async def message(self, thread_id: str, payload: StoryMessageIn) -> StoryThreadDeltaOut:
        thread = await self.get_thread(thread_id)
        if payload.style_code:
            thread.style_code = get_style_profile(payload.style_code).code
        user_turn = self._user_turn(thread, payload.text)
        thread.branch_path.append(payload.text)
        thread.turns.append(user_turn)
        assistant_turn = await self._generate_assistant_turn(
            thread,
            action_text=payload.text,
            context_hint="",
            parent_turn_id=user_turn.turn_id,
        )
        thread.turns.append(assistant_turn)
        thread.updated_at = datetime.utcnow()
        await self.repository.save_thread(thread)
        return StoryThreadDeltaOut(
            thread_id=thread.thread_id,
            appended_turns=[user_turn, assistant_turn],
            thread=thread,
        )

    async def _generate_assistant_turn(
        self,
        thread: StoryThreadOut,
        *,
        action_text: str,
        context_hint: str = "",
        parent_turn_id: str | None,
    ) -> StoryTurnOut:
        style = get_style_profile(thread.style_code)
        context_payload = BranchGenerationIn(
            episode_id=thread.episode_id,
            user_id=thread.user_id,
            ts_in_video=thread.ts_in_video,
            fork_id=thread.fork_id,
            selected_choice=action_text,
            branch_history=thread.branch_path,
            style=style.prompt,
        )
        context = await NarrativeContextBuilder(self.db).build(context_payload)
        turn_id = self._turn_id(thread.thread_id, "assistant")
        messages = build_story_chat_messages(
            thread,
            context,
            style,
            action_text,
            context_hint=context_hint,
        )
        try:
            raw = await tracked_chat_completion(
                self.db,
                messages,
                scene="story_chat",
                user_id=thread.user_id,
                episode_id=thread.episode_id,
                temperature=style.temperature,
                max_tokens=settings.story_chat_max_tokens,
                response_format={"type": "json_object"},
            )
            turn = parse_assistant_turn(
                raw,
                thread_id=thread.thread_id,
                turn_id=turn_id,
                parent_turn_id=parent_turn_id,
                context=context,
            )
            if turn.text:
                return turn
        except Exception as exc:
            logger.warning(
                "story chat generation fallback: thread=%s episode=%s error=%s",
                thread.thread_id,
                thread.episode_id,
                exc,
            )
        return fallback_assistant_turn(
            thread_id=thread.thread_id,
            turn_id=turn_id,
            parent_turn_id=parent_turn_id,
            action_text=action_text,
            context=context,
        )

    def _user_turn(
        self,
        thread: StoryThreadOut,
        text: str,
        *,
        selected_choice_id: str | None = None,
    ) -> StoryTurnOut:
        return StoryTurnOut(
            turn_id=self._turn_id(thread.thread_id, "user"),
            thread_id=thread.thread_id,
            role="user_choice",
            parent_turn_id=thread.turns[-1].turn_id if thread.turns else None,
            selected_choice_id=selected_choice_id,
            text=text,
            created_at=datetime.utcnow(),
        )

    def _thread_id(self, payload: StoryThreadCreateIn) -> str:
        basis = f"{payload.episode_id}:{payload.user_id}:{payload.ts_in_video}:{time.time_ns()}"
        digest = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:10]
        return f"thread_{payload.episode_id}_{int(payload.ts_in_video * 1000)}_{digest}"

    def _turn_id(self, thread_id: str, role: str) -> str:
        digest = hashlib.sha1(f"{thread_id}:{role}:{time.time_ns()}".encode("utf-8")).hexdigest()[:8]
        return f"turn_{role}_{digest}"
