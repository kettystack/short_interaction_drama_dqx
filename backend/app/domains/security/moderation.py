from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import ContentReviewItem, ModerationLog
from .schemas import ModerationResult


class ModerationService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def check_text(self, text: str, *, scene: str, user_id: str) -> ModerationResult:
        blocked = [w.strip() for w in settings.text_moderation_block_words.split(",") if w.strip()]
        reasons = [word for word in blocked if word and word in text]
        if reasons:
            result = ModerationResult(
                decision="review",
                risk_score=min(1.0, 0.45 + 0.18 * len(reasons)),
                reasons=reasons,
                masked_text=self._mask(text, reasons),
            )
        else:
            result = ModerationResult(decision="allow", risk_score=0.0, masked_text=text)
        self.db.add(
            ModerationLog(
                scene=scene,
                user_id=user_id,
                text=text[:1000],
                decision=result.decision,
                risk_score=result.risk_score,
                reasons=result.reasons,
            )
        )
        await self.db.commit()
        return result

    async def create_review_if_needed(
        self,
        result: ModerationResult,
        *,
        item_type: str,
        item_id: str,
        episode_id: str,
        user_id: str,
        text: str,
    ) -> ContentReviewItem | None:
        if result.decision == "allow":
            return None
        item = ContentReviewItem(
            item_type=item_type,
            item_id=item_id,
            episode_id=episode_id,
            user_id=user_id,
            text=text[:2000],
            status="pending",
            risk_score=result.risk_score,
            reason=",".join(result.reasons),
        )
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        return item

    def _mask(self, text: str, words: list[str]) -> str:
        value = text
        for word in words:
            value = value.replace(word, "*" * len(word))
        return value

