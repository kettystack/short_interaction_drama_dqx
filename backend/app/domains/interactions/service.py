from sqlalchemy.ext.asyncio import AsyncSession

from .effect_registry import LIKE_ACTION, display_count_for_action, effect_for_action, label_for_action
from .realtime import broadcast_interaction
from .repository import InteractionRepository
from .schemas import (
    InteractionIn,
    InteractionOut,
    InteractionSummaryOut,
    InteractionTimelineBucketOut,
    StoryFeedbackOut,
)
from .storm import maybe_fire_storm


class InteractionService:
    def __init__(self, db: AsyncSession) -> None:
        self.repo = InteractionRepository(db)

    async def submit(self, payload: InteractionIn) -> InteractionOut:
        if payload.client_event_id:
            existing = await self.repo.get_by_client_event_id(payload.client_event_id)
            if existing:
                return await self._to_out(existing)

        recent_duplicate = await self.repo.get_recent_duplicate(payload)
        if recent_duplicate:
            return await self._to_out(recent_duplicate)

        effect = effect_for_action(payload.action, payload.effect)
        event = await self.repo.create(payload, effect)
        result = await self._to_out(event)
        await broadcast_interaction(result)
        await maybe_fire_storm(payload.episode_id, payload.action)
        return result

    async def summary(
        self,
        episode_id: str,
        action: str,
        highlight_id: int | None = None,
    ) -> InteractionSummaryOut:
        count = await self._count_for_summary(episode_id, action, highlight_id)
        return InteractionSummaryOut(
            episode_id=episode_id,
            action=action,
            count=count,
            display_count=display_count_for_action(action, count),
            label=label_for_action(action),
        )

    async def multi_summary(
        self,
        episode_id: str,
        actions: list[str],
        highlight_id: int | None = None,
    ) -> dict[str, InteractionSummaryOut]:
        """一次返回多个 action 的汇总，减少客户端并行请求数。"""
        result: dict[str, InteractionSummaryOut] = {}
        for action in actions:
            result[action] = await self.summary(episode_id, action, highlight_id)
        return result

    async def timeline(
        self,
        episode_id: str,
        bucket_size: int,
        action: str | None = None,
    ) -> list[InteractionTimelineBucketOut]:
        safe_bucket_size = min(max(bucket_size, 5), 60)
        return await self.repo.timeline(episode_id, safe_bucket_size, action)

    async def story_feedback(self, episode_id: str, limit: int = 30) -> StoryFeedbackOut:
        likes = await self.repo.count(episode_id, "ai_story_like")
        comment_events = await self.repo.list_by_action(
            episode_id, "ai_story_comment", limit=limit
        )
        comments: list[dict] = []
        for ev in comment_events:
            payload = ev.payload_json or {}
            text = payload.get("comment") if isinstance(payload, dict) else None
            if not text:
                continue
            comments.append(
                {
                    "id": ev.id,
                    "user_id": ev.user_id,
                    "text": str(text)[:240],
                    "ts_in_video": ev.ts_in_video,
                    "created_at": ev.created_at.isoformat(),
                }
            )
        return StoryFeedbackOut(
            episode_id=episode_id, likes=likes, comments=comments
        )

    async def _to_out(self, event) -> InteractionOut:
        count = await self._count_for_summary(
            event.episode_id,
            event.action,
            event.highlight_id,
        )
        return InteractionOut(
            id=event.id,
            event_id=f"evt_{event.id}",
            client_event_id=event.client_event_id,
            episode_id=event.episode_id,
            highlight_id=event.highlight_id,
            action=event.action,
            effect=event.effect or effect_for_action(event.action),
            ts_in_video=event.ts_in_video,
            user_id=event.user_id,
            server_ts=event.created_at,
            created_at=event.created_at,
            count=count,
            display_count=display_count_for_action(event.action, count),
            payload=event.payload_json or {},
        )

    async def _count_for_summary(
        self,
        episode_id: str,
        action: str,
        highlight_id: int | None = None,
    ) -> int:
        # 「喜欢」是可取消状态，人数统计应来自当前 active 的用户动作，
        # 不能继续使用 interaction_events 的追加计数。
        if highlight_id is None and action in {LIKE_ACTION, "like", "点赞"}:
            return await self.repo.count_active_episode_actions(
                episode_id,
                (LIKE_ACTION, "like", "点赞"),
            )
        return await self.repo.count(episode_id, action, highlight_id)
