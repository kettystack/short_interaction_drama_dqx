from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import Episode
from .memory_retriever import retrieve_current_events, retrieve_recent_events
from .repository import NarrativeRepository
from .schemas import BranchGenerationContext, BranchGenerationIn


class NarrativeContextBuilder:
    def __init__(self, db: AsyncSession, repository: NarrativeRepository | None = None):
        self.db = db
        self.repository = repository or NarrativeRepository()

    async def build(self, payload: BranchGenerationIn) -> BranchGenerationContext:
        episode = await self.db.get(Episode, payload.episode_id)
        if episode is None:
            raise HTTPException(404, f"episode not exists: {payload.episode_id}")

        events = self.repository.load_events(payload.episode_id)
        current_events = retrieve_current_events(events, payload.ts_in_video)
        recent_events = retrieve_recent_events(events, payload.ts_in_video)
        role_cards = self.repository.load_role_cards(episode.drama_id)
        previous_summary = self.repository.previous_summary(episode.drama_id, episode.id)

        return BranchGenerationContext(
            episode_id=payload.episode_id,
            current_time=payload.ts_in_video,
            drama_title=episode.drama_id,
            episode_title=episode.title,
            role_cards=role_cards,
            previous_summary=previous_summary,
            current_scene_events=current_events,
            recent_events=recent_events,
            selected_choice=payload.selected_choice,
            branch_history=payload.branch_history,
            style=payload.style,
        )
