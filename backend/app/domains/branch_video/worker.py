from __future__ import annotations

import hashlib
import json
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import (
    AigcVideoJob,
    BranchVideoVariant,
    PersonalizedBranchOption,
    PersonalizedBranchSession,
)
from ..aigc_video.schemas import AigcVideoJobCreateIn
from ..aigc_video.service import AigcVideoService
from ..security.schemas import CurrentUser
from .cache import build_variant_cache_key
from .quality_policy import sync_variant_from_job
from .repository import BranchVideoRepository
from .schemas import BranchOptionPlan, BranchVideoContext
from .shot_planner import build_shot_plan
from .story_planner import build_branch_story


class BranchVideoWorker:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.repo = BranchVideoRepository(db)

    async def generate_option(
        self,
        *,
        session: PersonalizedBranchSession,
        option: PersonalizedBranchOption,
        user: CurrentUser,
        target_duration: float,
    ) -> BranchVideoVariant:
        context = BranchVideoContext.model_validate(session.context_snapshot or {})
        plan = BranchOptionPlan(
            option_key=option.option_key,
            label=option.label,
            description=option.description,
            action=str((option.intent or {}).get("action") or option.label),
            emotion=str((option.intent or {}).get("emotion") or "紧张"),
            relationship_change=str((option.intent or {}).get("relationship_change") or ""),
            expected_hook=str((option.intent or {}).get("expected_hook") or ""),
            preview=str((option.intent or {}).get("preview") or option.description),
        )
        cache_key = build_variant_cache_key(
            context,
            plan,
            duration=target_duration,
            prompt_version=session.prompt_version,
        )
        current_variant = await self.repo.published_variant(option.id)
        if current_variant and current_variant.output_video_url:
            option.status = "ready"
            option.error_message = ""
            await self.db.commit()
            return current_variant
        cached = await self.repo.variant_by_cache_key(cache_key)
        if cached and cached.publish_status == "published" and cached.output_video_url:
            if cached.option_id != option.id:
                cached = BranchVideoVariant(
                    id=_variant_id(option.id, cache_key),
                    option_id=option.id,
                    aigc_job_id=cached.aigc_job_id,
                    provider=cached.provider,
                    model=cached.model,
                    source_frame_url=cached.source_frame_url,
                    output_video_url=cached.output_video_url,
                    duration=cached.duration,
                    quality_score=cached.quality_score,
                    quality_detail=dict(cached.quality_detail or {}),
                    review_status=cached.review_status,
                    publish_status=cached.publish_status,
                    cache_key=f"{cache_key}:{hashlib.sha1(option.id.encode()).hexdigest()[:10]}",
                )
                self.db.add(cached)
            option.status = "ready"
            option.error_message = ""
            await self.db.commit()
            await self.db.refresh(cached)
            return cached

        story = await build_branch_story(
            self.db,
            context,
            plan,
            user_id=session.user_id,
        )
        shot_plan = build_shot_plan(
            context,
            story,
            target_duration=target_duration,
        )
        option.story_plan = story.model_dump(mode="json")
        option.shot_plan = shot_plan.model_dump(mode="json")
        option_intent = dict(option.intent or {})
        generation_attempt = int(option_intent.get("_generation_attempt") or 0) + 1
        option_intent["_generation_attempt"] = generation_attempt
        option.intent = option_intent
        option.status = "submitting"
        option.error_message = ""
        option.updated_at = datetime.utcnow()
        await self.db.commit()

        prompt = _generation_prompt(context, plan, story.model_dump(), shot_plan.model_dump())
        job_out = await AigcVideoService(self.db).create_job(
            AigcVideoJobCreateIn(
                episode_id=session.episode_id,
                user_id=session.user_id,
                ts_in_video=session.trigger_ts,
                trigger_type="personalized_branch",
                user_prompt=prompt,
                style_code="cinematic_literary",
                highlight_id=session.highlight_id,
                idempotency_key=f"branch-video:{cache_key}:attempt:{generation_attempt}",
                duration_seconds=target_duration,
            ),
            user,
        )
        job = await self.db.get(AigcVideoJob, job_out.job_id)
        if job is None:
            raise RuntimeError("AIGC job was not persisted")

        variant = await self.repo.variant_by_cache_key(cache_key)
        if variant is None:
            variant = BranchVideoVariant(
                id=_variant_id(option.id, cache_key),
                option_id=option.id,
                aigc_job_id=job.id,
                provider=job.provider,
                model=settings.aigc_video_model,
                source_frame_url=context.source_frame_url,
                cache_key=cache_key,
            )
            self.db.add(variant)
        else:
            variant.option_id = option.id
            variant.aigc_job_id = job.id
        sync_variant_from_job(option, variant, job)
        option.updated_at = datetime.utcnow()
        variant.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(variant)
        return variant

    async def sync_option(
        self,
        option: PersonalizedBranchOption,
    ) -> BranchVideoVariant | None:
        variant = await self.repo.latest_variant(option.id)
        if variant is None:
            if option.status in {
                "submitting",
                "submitted",
                "generating",
                "downloading",
                "transcoding",
                "quality_checking",
            }:
                option.status = "failed"
                option.error_message = "生成任务关联中断，已允许自动重新提交"
                option.updated_at = datetime.utcnow()
                await self.db.commit()
            return None
        if not variant.aigc_job_id:
            return variant
        job = await self.db.get(AigcVideoJob, variant.aigc_job_id)
        if job is None:
            option.status = "failed"
            option.error_message = "关联的视频生成任务不存在"
            await self.db.commit()
            return variant
        resumable_processing = job.status in {
            "downloading",
            "transcoding",
            "quality_checking",
        } and (
            job.updated_at is None
            or (datetime.utcnow() - job.updated_at).total_seconds() >= 180
        )
        if job.status in {
            "queued",
            "context_ready",
            "intent_ready",
            "submitted",
            "generating",
        } or resumable_processing:
            await AigcVideoService(self.db).advance_job(job.id)
            job = await self.db.get(AigcVideoJob, job.id)
            if job is None:
                return variant
        sync_variant_from_job(option, variant, job)
        option.updated_at = datetime.utcnow()
        variant.updated_at = datetime.utcnow()
        await self.db.commit()
        return variant


def _generation_prompt(context, option, story: dict, shot_plan: dict) -> str:
    payload = {
        "branch_option": option.model_dump(mode="json"),
        "story_plan": story,
        "shot_plan": shot_plan,
        "manual_continuity_context": context.manual_context,
    }
    return (
        "严格从输入的正片首帧开始生成，不得退化为随机文生视频。"
        "保持同一角色、服装、场景和人物关系。"
        "这是正片中的个性化剧情插片，必须表现具体动作、人物反应、"
        "可见结果和规划中的短对白；执行所选行为后留下悬念，"
        "结尾不得制造阻止回到原正片的不可逆事实。"
        f"\n当前冲突：{context.current_conflict}"
        f"\n结构化规划：{json.dumps(payload, ensure_ascii=False)}"
    )


def _variant_id(option_id: str, cache_key: str) -> str:
    digest = hashlib.sha1(f"{option_id}:{cache_key}".encode("utf-8")).hexdigest()[:12]
    return f"bvv_{digest}"
