from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...models import InteractionEvent, UserEpisodeAction
from .effect_registry import actions_for_count, display_count_for_action, effect_for_action
from .schemas import InteractionIn, InteractionTimelineBucketOut


DEDUP_WINDOW_SECONDS = 0.45


class InteractionRepository:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get_by_client_event_id(self, client_event_id: str) -> InteractionEvent | None:
        return await self.db.scalar(
            select(InteractionEvent)
            .where(InteractionEvent.client_event_id == client_event_id)
            .order_by(InteractionEvent.id.desc())
            .limit(1)
        )

    async def get_recent_duplicate(self, payload: InteractionIn) -> InteractionEvent | None:
        return await self.db.scalar(
            select(InteractionEvent)
            .where(
                InteractionEvent.episode_id == payload.episode_id,
                InteractionEvent.user_id == payload.user_id,
                InteractionEvent.action == payload.action,
                InteractionEvent.created_at >= datetime.utcnow() - timedelta(seconds=DEDUP_WINDOW_SECONDS),
            )
            .order_by(InteractionEvent.id.desc())
            .limit(1)
        )

    async def create(self, payload: InteractionIn, effect: str | None) -> InteractionEvent:
        event = InteractionEvent(
            client_event_id=payload.client_event_id,
            episode_id=payload.episode_id,
            highlight_id=payload.highlight_id,
            action=payload.action,
            effect=effect,
            ts_in_video=payload.ts_in_video,
            user_id=payload.user_id,
            payload_json=payload.payload,
        )
        self.db.add(event)
        await self.db.commit()
        await self.db.refresh(event)
        return event

    async def count(self, episode_id: str, action: str, highlight_id: int | None = None) -> int:
        stmt = select(InteractionEvent.id).where(
            InteractionEvent.episode_id == episode_id,
            InteractionEvent.action.in_(actions_for_count(action)),
        )
        if highlight_id is not None:
            stmt = stmt.where(InteractionEvent.highlight_id == highlight_id)
        result = await self.db.execute(stmt)
        return len(result.scalars().all())

    async def count_active_episode_actions(
        self,
        episode_id: str,
        actions: tuple[str, ...],
    ) -> int:
        stmt = select(UserEpisodeAction.id).where(
            UserEpisodeAction.episode_id == episode_id,
            UserEpisodeAction.active.is_(True),
            UserEpisodeAction.action.in_(actions),
        )
        result = await self.db.execute(stmt)
        return len(result.scalars().all())

    async def list_by_action(
        self,
        episode_id: str,
        action: str,
        limit: int = 50,
    ) -> list[InteractionEvent]:
        stmt = (
            select(InteractionEvent)
            .where(
                InteractionEvent.episode_id == episode_id,
                InteractionEvent.action == action,
            )
            .order_by(InteractionEvent.id.desc())
            .limit(max(1, min(limit, 200)))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def timeline(
        self,
        episode_id: str,
        bucket_size: int,
        action: str | None = None,
    ) -> list[InteractionTimelineBucketOut]:
        stmt = select(InteractionEvent).where(InteractionEvent.episode_id == episode_id)
        if action:
            stmt = stmt.where(InteractionEvent.action.in_(actions_for_count(action)))
        result = await self.db.execute(stmt)
        buckets: dict[tuple[float, str], int] = {}
        effects: dict[tuple[float, str], str | None] = {}
        dominant_actions: dict[float, dict[str, int]] = {}

        for event in result.scalars().all():
            bucket_start = float(int(event.ts_in_video // bucket_size) * bucket_size)
            bucket_action = event.action if action else "互动热力"
            key = (bucket_start, bucket_action)
            buckets[key] = buckets.get(key, 0) + 1
            action_counts = dominant_actions.setdefault(bucket_start, {})
            action_counts[event.action] = action_counts.get(event.action, 0) + 1

            if action:
                effects[key] = event.effect or effect_for_action(event.action)

        if not action:
            for bucket_start, bucket_action in buckets:
                action_counts = dominant_actions.get(bucket_start, {})
                dominant_action = max(action_counts, key=action_counts.get) if action_counts else bucket_action
                effects[(bucket_start, bucket_action)] = effect_for_action(dominant_action)

        return [
            InteractionTimelineBucketOut(
                episode_id=episode_id,
                bucket_start=bucket_start,
                bucket_size=bucket_size,
                action=bucket_action,
                effect=effects.get((bucket_start, bucket_action)),
                count=count,
                display_count=display_count_for_action(bucket_action, count) if action else count,
            )
            for (bucket_start, bucket_action), count in sorted(buckets.items())
        ]
