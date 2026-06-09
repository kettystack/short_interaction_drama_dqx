from __future__ import annotations

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import StoryThreadModel, StoryTurnModel
from .repository import StoryChatRepository
from .schemas import StoryChoiceOut, StoryThreadOut, StoryTurnOut


class StoryChatDbRepository:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.file_fallback = StoryChatRepository()

    async def get_thread(self, thread_id: str) -> StoryThreadOut | None:
        thread = await self.db.get(StoryThreadModel, thread_id)
        if thread is None:
            fallback = self.file_fallback.get_thread(thread_id)
            if fallback is not None:
                await self.save_thread(fallback)
            return fallback
        turn_result = await self.db.execute(
            select(StoryTurnModel)
            .where(StoryTurnModel.thread_id == thread_id)
            .order_by(StoryTurnModel.created_at)
        )
        turns = [self._turn_to_out(turn) for turn in turn_result.scalars().all()]
        return StoryThreadOut(
            thread_id=thread.id,
            episode_id=thread.episode_id,
            user_id=thread.user_id,
            fork_id=thread.fork_id,
            ts_in_video=thread.ts_in_video,
            style_code=thread.style_code,
            title=thread.title,
            turns=turns,
            branch_path=thread.branch_path or [],
            created_at=thread.created_at,
            updated_at=thread.updated_at,
        )

    async def save_thread(self, thread: StoryThreadOut) -> StoryThreadOut:
        existing = await self.db.get(StoryThreadModel, thread.thread_id)
        if existing is None:
            existing = StoryThreadModel(id=thread.thread_id)
            self.db.add(existing)
        existing.episode_id = thread.episode_id
        existing.user_id = thread.user_id
        existing.fork_id = thread.fork_id
        existing.ts_in_video = thread.ts_in_video
        existing.style_code = thread.style_code
        existing.title = thread.title
        existing.branch_path = list(thread.branch_path)
        existing.created_at = thread.created_at
        existing.updated_at = thread.updated_at

        await self.db.execute(
            delete(StoryTurnModel).where(StoryTurnModel.thread_id == thread.thread_id)
        )
        for turn in thread.turns:
            self.db.add(
                StoryTurnModel(
                    id=turn.turn_id,
                    thread_id=turn.thread_id,
                    role=turn.role,
                    parent_turn_id=turn.parent_turn_id,
                    selected_choice_id=turn.selected_choice_id,
                    text=turn.text,
                    choices=[choice.model_dump(mode="json") for choice in turn.choices],
                    evidence_event_ids=list(turn.evidence_event_ids),
                    created_at=turn.created_at,
                )
            )
        await self.db.commit()
        self.file_fallback.save_thread(thread)
        return thread

    async def list_user_threads(self, user_id: str, limit: int = 50) -> list[StoryThreadOut]:
        result = await self.db.execute(
            select(StoryThreadModel)
            .where(StoryThreadModel.user_id == user_id)
            .order_by(StoryThreadModel.updated_at.desc())
            .limit(min(limit, 100))
        )
        threads: list[StoryThreadOut] = []
        for row in result.scalars().all():
            thread = await self.get_thread(row.id)
            if thread:
                threads.append(thread)
        return threads

    def _turn_to_out(self, turn: StoryTurnModel) -> StoryTurnOut:
        return StoryTurnOut(
            turn_id=turn.id,
            thread_id=turn.thread_id,
            role=turn.role,  # type: ignore[arg-type]
            parent_turn_id=turn.parent_turn_id,
            selected_choice_id=turn.selected_choice_id,
            text=turn.text,
            choices=[StoryChoiceOut.model_validate(choice) for choice in (turn.choices or [])],
            evidence_event_ids=turn.evidence_event_ids or [],
            created_at=turn.created_at,
        )

