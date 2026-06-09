from __future__ import annotations

import hashlib
import time

from sqlalchemy.ext.asyncio import AsyncSession

from ...services.ai_service import chat_completion
from .context_builder import NarrativeContextBuilder
from .prompt_builder import build_branch_generation_messages
from .quality_guard import fallback_branch_story, parse_branch_story
from .repository import NarrativeRepository
from .schemas import BranchGenerationIn, BranchStoryOut


class BranchGenerationService:
    def __init__(self, db: AsyncSession, repository: NarrativeRepository | None = None):
        self.db = db
        self.repository = repository or NarrativeRepository()

    async def generate(self, payload: BranchGenerationIn) -> BranchStoryOut:
        context = await NarrativeContextBuilder(self.db, self.repository).build(payload)
        story_id = self._story_id(payload)
        messages = build_branch_generation_messages(context)
        try:
            raw = await chat_completion(messages, temperature=0.72)
            story = parse_branch_story(raw, context, story_id)
            if not story.text:
                return fallback_branch_story(context, story_id, "模型返回为空，已使用证据链兜底续写")
            return story
        except Exception as exc:
            return fallback_branch_story(context, story_id, f"AI 生成失败，已使用本地兜底：{type(exc).__name__}")

    def _story_id(self, payload: BranchGenerationIn) -> str:
        basis = f"{payload.episode_id}:{payload.ts_in_video}:{payload.selected_choice}:{time.time_ns()}"
        digest = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:10]
        return f"story_{payload.episode_id}_{int(payload.ts_in_video * 1000)}_{digest}"
