from __future__ import annotations

import asyncio
import hashlib
import time
from datetime import datetime
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import AigcBoostPoint, AigcQualityCheck, AigcVideoJob, Episode, Highlight
from ..security.moderation import ModerationService
from ..security.rate_limit import check_rate_limit
from ..security.schemas import CurrentUser
from .asset_resolver import resolve_clip_asset
from .context_builder import build_generation_context, require_frame_context
from .intent_planner import plan_video_intent
from .prompt_builder import build_aigc_video_prompt
from .providers.jimeng import JimengVideoGenerationProvider
from .providers.mock import MockVideoGenerationProvider
from .quality_gate import validate_clip, validate_provider_clip
from .schemas import (
    AigcBoostPointCreateIn,
    AigcBoostPointOut,
    AigcVideoJobCreateIn,
    AigcVideoJobOut,
    ClipCandidate,
    VideoGenerationRequest,
)
from .transcoder import compare_frame_ssim, normalize_and_inspect_video

_JOB_ADVANCE_LOCKS: dict[str, asyncio.Lock] = {}


class AigcVideoService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def create_job(
        self,
        payload: AigcVideoJobCreateIn,
        user: CurrentUser,
    ) -> AigcVideoJobOut:
        await check_rate_limit(
            self.db,
            user,
            "aigc_video",
            limit=8,
            window_seconds=3600,
        )
        episode = await self.db.get(Episode, payload.episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")
        highlight = await self.db.get(Highlight, payload.highlight_id) if payload.highlight_id else None
        moderation = await ModerationService(self.db).check_text(
            payload.user_prompt,
            scene="aigc_video_prompt",
            user_id=payload.user_id or user.user_id,
        )
        if moderation.decision == "review" and moderation.risk_score >= 0.85:
            raise HTTPException(400, "prompt needs review before generation")

        if payload.idempotency_key:
            existing = await self._get_by_source_key(payload.idempotency_key)
            if existing:
                return self._to_out(existing)

        job_id = self._job_id(payload)
        context = await build_generation_context(
            self.db,
            episode=episode,
            ts_in_video=payload.ts_in_video,
            trigger_type=payload.trigger_type,
            highlight=highlight,
            story_thread_id=payload.story_thread_id,
        )
        requested_duration = (
            payload.duration_seconds
            if payload.duration_seconds is not None
            else settings.aigc_insert_duration_seconds
        )
        generation_duration = max(
            2.0,
            min(
                float(requested_duration),
                float(settings.aigc_video_provider_max_duration_seconds),
                15.0,
            ),
        )
        intent = plan_video_intent(
            context=context,
            user_prompt=payload.user_prompt,
            duration_seconds=generation_duration,
        )
        prompt = intent.prompt or build_aigc_video_prompt(
            episode=episode,
            highlight=highlight,
            trigger_type=payload.trigger_type,
            user_prompt=payload.user_prompt,
            style_code=payload.style_code,
        )
        job = AigcVideoJob(
            id=job_id,
            episode_id=payload.episode_id,
            user_id=payload.user_id or user.user_id,
            ts_in_video=max(payload.ts_in_video, 0),
            trigger_type=payload.trigger_type,
            prompt=prompt,
            source_context={
                "highlight_id": payload.highlight_id,
                "story_thread_id": payload.story_thread_id,
                "style_code": payload.style_code,
                "idempotency_key": payload.idempotency_key,
                "requested_duration_seconds": requested_duration,
                "generation_duration_seconds": generation_duration,
                "duration_was_clamped": generation_duration != requested_duration,
                "moderation": moderation.model_dump(),
                "generation_context": context.model_dump(),
                "insert_intent": intent.model_dump(),
                "status_history": [
                    self._status_event("queued", 0.0, "任务已创建"),
                    self._status_event("context_ready", 0.08, "剧情上下文和正片帧已准备"),
                    self._status_event("intent_ready", 0.15, "结构化镜头意图已准备"),
                ],
            },
            provider=self._provider_name(),
            status="intent_ready",
            progress=0.15,
            resume_at=context.resume_at,
            updated_at=datetime.utcnow(),
        )
        self.db.add(job)
        await self.db.commit()
        await self.db.refresh(job)
        await self.advance_job(job.id)
        ready = await self.db.get(AigcVideoJob, job.id)
        if ready is None:
            raise HTTPException(500, "job lost")
        return self._to_out(ready)

    async def get_job(self, job_id: str, user: CurrentUser) -> AigcVideoJobOut:
        job = await self.db.get(AigcVideoJob, job_id)
        if job is None:
            raise HTTPException(404, "aigc job not found")
        if not user.is_admin and job.user_id != user.user_id and user.user_id != "anon":
            raise HTTPException(403, "cannot access this job")
        if job.status in {"submitted", "generating"}:
            return await self.advance_job(job.id)
        return self._to_out(job)

    async def list_jobs(
        self,
        *,
        episode_id: str | None = None,
        status: str | None = None,
        limit: int = 50,
    ) -> list[AigcVideoJobOut]:
        stmt = select(AigcVideoJob)
        if episode_id:
            stmt = stmt.where(AigcVideoJob.episode_id == episode_id)
        if status:
            stmt = stmt.where(AigcVideoJob.status == status)
        result = await self.db.execute(stmt.order_by(AigcVideoJob.created_at.desc()).limit(min(limit, 100)))
        return [self._to_out(job) for job in result.scalars().all()]

    async def review_job(
        self,
        job_id: str,
        *,
        approve: bool,
        reviewer: CurrentUser,
        reason: str = "",
    ) -> AigcVideoJobOut:
        job = await self.db.get(AigcVideoJob, job_id)
        if job is None:
            raise HTTPException(404, "aigc job not found")
        if job.status != "review_required":
            raise HTTPException(400, "only review_required jobs can be reviewed")
        if approve and not job.output_video_url:
            raise HTTPException(400, "review candidate has no output video")
        review = {
            "decision": "approved" if approve else "rejected",
            "reviewer": reviewer.user_id,
            "reason": reason.strip()[:500],
            "reviewed_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        }
        job.source_context = {
            **(job.source_context or {}),
            "human_review": review,
            "quality_decision": "human_approved" if approve else "human_rejected",
        }
        if approve:
            self._set_job_status(job, "ready", 1.0, "人工审核通过，可以发布")
            job.error_message = ""
        else:
            self._set_job_status(job, "failed", 1.0, "人工审核拒绝候选视频")
            job.error_message = reason.strip() or "人工审核未通过"
        job.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(job)
        return self._to_out(job)

    async def list_boost_points(
        self,
        *,
        episode_id: str,
        include_unpublished: bool = False,
        limit: int = 50,
    ) -> list[AigcBoostPointOut]:
        stmt = select(AigcBoostPoint).where(AigcBoostPoint.episode_id == episode_id)
        if not include_unpublished:
            stmt = stmt.where(AigcBoostPoint.status == "published")
        if settings.aigc_video_real_enabled and not settings.aigc_video_fallback_to_assets:
            stmt = stmt.where(AigcBoostPoint.provider.in_(["seedance", "jimeng", "ark_video"]))
        result = await self.db.execute(
            stmt.order_by(AigcBoostPoint.trigger_ts.asc(), AigcBoostPoint.updated_at.desc()).limit(min(limit, 100))
        )
        points: list[AigcBoostPointOut] = []
        seen_triggers: set[int] = set()
        for point in result.scalars().all():
            trigger_key = int(point.trigger_ts * 1000)
            if trigger_key in seen_triggers:
                continue
            seen_triggers.add(trigger_key)
            points.append(self._to_boost_out(point))
        return points

    async def create_boost_point(
        self,
        payload: AigcBoostPointCreateIn,
        user: CurrentUser,
    ) -> AigcBoostPointOut:
        episode = await self.db.get(Episode, payload.episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")

        source_job: AigcVideoJob | None = None
        if payload.source_job_id:
            source_job = await self.db.get(AigcVideoJob, payload.source_job_id)
            if source_job is None:
                raise HTTPException(404, "source AIGC job not found")
            if source_job.status != "ready" or not source_job.output_video_url:
                raise HTTPException(400, "source AIGC job is not ready")
            if source_job.episode_id != payload.episode_id:
                raise HTTPException(400, "source AIGC job belongs to another episode")

        output_video_url = payload.output_video_url or (source_job.output_video_url if source_job else "")
        if not output_video_url:
            raise HTTPException(400, "boost point needs output_video_url or a ready source_job_id")

        resume_at = (
            payload.resume_at
            if payload.resume_at is not None
            else (source_job.resume_at if source_job else payload.trigger_ts)
        )
        duration = payload.duration or (source_job.duration if source_job else 0.0)
        provider = payload.provider or (source_job.provider if source_job else self._provider_name())
        prompt = payload.prompt or (source_job.prompt if source_job else "")
        quality_score = payload.quality_score
        if source_job and quality_score <= 0:
            quality_score = await self._quality_score_for_job(source_job)

        point_id = self._boost_point_id(episode_id=payload.episode_id, trigger_ts=payload.trigger_ts)
        point = await self.db.get(AigcBoostPoint, point_id)
        if point is None:
            point = AigcBoostPoint(id=point_id, created_at=datetime.utcnow())
            self.db.add(point)
        point.episode_id = payload.episode_id
        point.trigger_ts = max(payload.trigger_ts, 0.0)
        point.resume_at = max(resume_at or payload.trigger_ts, 0.0)
        point.title = payload.title or "加速包"
        point.prompt = prompt
        point.provider = provider
        point.source_job_id = payload.source_job_id or ""
        point.output_video_url = output_video_url
        point.hls_url = payload.hls_url or (source_job.hls_url if source_job else "")
        point.cover_url = payload.cover_url or (source_job.cover_url if source_job else "")
        point.duration = max(duration or 0.0, 0.0)
        point.quality_score = round(max(quality_score or 0.0, 0.0), 4)
        point.status = payload.status or "published"
        point.raw = {
            **(payload.raw or {}),
            "published_by": user.user_id,
            "source_job": self._source_job_summary(source_job),
        }
        point.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(point)
        return self._to_boost_out(point)

    async def advance_job(self, job_id: str) -> AigcVideoJobOut:
        lock = _JOB_ADVANCE_LOCKS.setdefault(job_id, asyncio.Lock())
        async with lock:
            return await self._advance_job_locked(job_id)

    async def _advance_job_locked(self, job_id: str) -> AigcVideoJobOut:
        job = await self.db.get(AigcVideoJob, job_id)
        if job is None:
            raise HTTPException(404, "aigc job not found")
        # Provider polling, download and quality checks can take minutes. Release
        # the checked-out connection before doing remote or media work.
        await self.db.commit()
        provider = self._provider()
        previous_status = job.status
        try:
            if job.status in {"queued", "context_ready", "intent_ready"}:
                if self._should_submit_real_provider():
                    await self._submit_real_provider(job, provider)
                else:
                    await self._attach_asset_fallback(job, reason="real_provider_disabled")
            elif job.status in {"submitted", "generating"} and job.provider_job_id:
                status = await provider.poll(job.provider_job_id)
                if status.status == "failed":
                    if settings.aigc_video_fallback_to_assets:
                        await self._attach_asset_fallback(job, reason="provider_failed")
                    else:
                        self._set_job_status(job, "failed", 1.0, "真实视频生成失败")
                        job.error_message = "真实视频生成失败"
                elif status.status == "ready" and status.output_video_url:
                    await self._attach_provider_output(
                        job,
                        output_video_url=status.output_video_url,
                        duration=status.duration,
                        cover_url=status.cover_url,
                    )
                else:
                    self._set_job_status(
                        job,
                        "generating",
                        max(float(status.progress or 0.0), 0.25),
                        "Seedance 正在生成候选视频",
                    )
            elif job.status in {
                "downloading",
                "transcoding",
                "quality_checking",
            }:
                source_url = self._local_provider_source_url(job)
                if source_url:
                    await self._attach_provider_output(
                        job,
                        output_video_url=source_url,
                        duration=job.duration,
                        cover_url=job.cover_url,
                    )
                else:
                    self._set_job_status(job, "failed", 1.0, "生成处理中断，源视频不存在")
                    job.error_message = "生成处理中断且未找到已下载的供应商源视频"
            job.updated_at = datetime.utcnow()
        except Exception as exc:
            error_text = f"{type(exc).__name__}: {exc}".strip()
            if settings.aigc_video_fallback_to_assets:
                job.source_context = {
                    **(job.source_context or {}),
                    "provider_error": error_text[:500],
                }
                await self._attach_asset_fallback(job, reason="provider_exception")
            elif job.provider_job_id and previous_status in {"submitted", "generating"}:
                source_context = dict(job.source_context or {})
                retry_count = int(source_context.get("provider_retry_count") or 0) + 1
                source_context["provider_retry_count"] = retry_count
                source_context["provider_error"] = error_text[:500]
                job.source_context = source_context
                if retry_count <= 3:
                    self._set_job_status(
                        job,
                        "generating",
                        max(job.progress, 0.35),
                        f"生成结果处理暂时失败，正在自动重试（{retry_count}/3）",
                    )
                    job.error_message = error_text[:500]
                else:
                    self._set_job_status(job, "failed", 1.0, "任务重试次数已耗尽")
                    job.error_message = error_text[:500]
            else:
                self._set_job_status(job, "failed", 1.0, "任务执行异常")
                job.error_message = error_text[:500]
            job.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(job)
        return self._to_out(job)

    async def _submit_real_provider(self, job: AigcVideoJob, provider) -> None:
        context = await self._context_for_job(job)
        if settings.aigc_video_require_first_frame:
            require_frame_context(context)
        if not self._history_contains(job, "context_ready"):
            self._set_job_status(job, "context_ready", 0.08, "正片首帧已准备")
        if not self._history_contains(job, "intent_ready"):
            self._set_job_status(job, "intent_ready", 0.15, "镜头意图与生成提示词已准备")
        request = VideoGenerationRequest(
            job_id=job.id,
            episode_id=job.episode_id,
            prompt=job.prompt,
            trigger_type=job.trigger_type,
            style_code=str((job.source_context or {}).get("style_code") or "short_drama_punchy"),
            source_context=job.source_context or {},
            first_frame_url=context.first_frame_url,
            last_frame_url=context.last_frame_url,
            first_frame_path=context.first_frame_path,
            last_frame_path=context.last_frame_path,
            generation_mode="first_frame_to_video",
            duration=self._intent_for_job(job, context).duration_seconds,
            ratio="9:16",
        )
        await self.db.commit()
        provider_job = await provider.submit(request)
        job.provider_job_id = provider_job.provider_job_id
        job.provider = self._provider_name()
        self._set_job_status(
            job,
            "submitted",
            max(float(provider_job.progress or 0.0), 0.2),
            "首帧图生视频任务已提交 Seedance",
        )
        if provider_job.status == "ready" and provider_job.output_video_url:
            await self._attach_provider_output(
                job,
                output_video_url=provider_job.output_video_url,
                duration=provider_job.duration,
                cover_url=provider_job.cover_url,
            )

    async def _attach_provider_output(
        self,
        job: AigcVideoJob,
        *,
        output_video_url: str,
        duration: float = 0.0,
        cover_url: str = "",
    ) -> None:
        context = await self._context_for_job(job)
        intent = self._intent_for_job(job, context)
        self._set_job_status(job, "downloading", 0.72, "正在下载供应商候选视频")
        await self.db.commit()
        source_path = await self._materialize_provider_output(job, output_video_url)
        self._set_job_status(job, "transcoding", 0.8, "正在转码为播放器标准竖屏 MP4")
        generated_root = Path(settings.generated_media_root).resolve()
        final_path, technical, review_frames = await normalize_and_inspect_video(
            source_path=source_path,
            target_path=generated_root / "aigc" / f"{job.id}.mp4",
            review_dir=generated_root / "review" / job.id,
        )
        local_url = f"/generated/aigc/{final_path.name}"
        review_urls = [
            f"/generated/review/{job.id}/{frame.name}"
            for frame in review_frames
        ]
        if review_frames and context.first_frame_path:
            technical["first_frame_ssim"] = await compare_frame_ssim(
                Path(context.first_frame_path),
                review_frames[0],
            )
        candidate = ClipCandidate(
            clip_id=f"provider_{job.provider_job_id or job.id}",
            clip_url=local_url,
            episode_id=job.episode_id,
            drama_id=context.drama_id,
            ts_start=context.ts_in_video,
            ts_end=context.resume_at,
            duration=float(technical.get("duration") or duration or settings.aigc_insert_duration_seconds),
            score=0.72,
            source="provider_generated",
            provider=self._provider_name(),
            match_reasons=["真实 provider 正片首帧图生视频", "已下载并转码为本地播放器素材"],
        )
        self._set_job_status(job, "quality_checking", 0.9, "正在进行多模态质量评估")
        source_first_frame = Path(context.first_frame_path)
        source_resume_frame = Path(context.last_frame_path) if context.last_frame_path else None
        gate = await validate_provider_clip(
            self.db,
            job_id=job.id,
            context=context,
            intent=intent,
            candidate=candidate,
            source_first_frame=source_first_frame,
            source_resume_frame=source_resume_frame,
            generated_frames=review_frames,
            technical=technical,
        )
        job.output_video_url = local_url
        job.duration = candidate.duration
        job.cover_url = review_urls[0] if review_urls else cover_url
        job.source_context = {
            **(job.source_context or {}),
            "resolved_candidate": candidate.model_dump(),
            "quality_gate": gate.model_dump(),
            "quality_score": round(gate.score, 4),
            "quality_decision": gate.decision,
            "review_frames": review_urls,
            "provider_output_url": output_video_url,
        }
        if gate.decision == "review":
            self._set_job_status(job, "review_required", 1.0, "候选视频等待人工审核")
            job.error_message = "多模态质量闸门要求人工审核"
            return
        if gate.decision != "pass":
            self._set_job_status(job, "failed", 1.0, "候选视频未通过质量闸门")
            job.error_message = "真实生成质量闸门未通过：" + "；".join(gate.reasons)
            return
        self._apply_candidate(job, candidate, gate_score=gate.score)
        if not job.cover_url:
            job.cover_url = cover_url

    async def _attach_asset_fallback(self, job: AigcVideoJob, *, reason: str) -> None:
        context = await self._context_for_job(job)
        intent = self._intent_for_job(job, context)
        candidate = await resolve_clip_asset(
            self.db,
            context=context,
            intent=intent,
            allow_branch_fallback=True,
        )
        if candidate is None:
            self._set_job_status(job, "failed", 1.0, "没有可用的兜底素材")
            job.output_video_url = ""
            job.duration = 0.0
            job.error_message = "当前剧集没有可用同集 clip_assets 或分支兜底素材，已阻止错配播放"
            job.source_context = {**(job.source_context or {}), "fallback_reason": reason}
            return
        gate = await validate_clip(
            self.db,
            job_id=job.id,
            context=context,
            intent=intent,
            candidate=candidate,
        )
        if gate.decision != "pass":
            self._set_job_status(job, "failed", 1.0, "兜底素材未通过质量闸门")
            job.output_video_url = ""
            job.duration = 0.0
            job.error_message = "素材质量闸门未通过：" + "；".join(gate.reasons)
            job.source_context = {
                **(job.source_context or {}),
                "fallback_reason": reason,
                "rejected_candidate": candidate.model_dump(),
            }
            return
        self._apply_candidate(job, candidate, gate_score=gate.score)
        job.source_context = {
            **(job.source_context or {}),
            "fallback_reason": reason,
            "quality_gate": gate.model_dump(),
        }

    def _apply_candidate(
        self,
        job: AigcVideoJob,
        candidate: ClipCandidate,
        *,
        gate_score: float,
    ) -> None:
        self._set_job_status(job, "ready", 1.0, "质量闸门通过，可以发布")
        job.output_video_url = candidate.clip_url
        job.duration = candidate.duration or settings.aigc_insert_duration_seconds
        job.hls_url = ""
        job.error_message = ""
        job.source_context = {
            **(job.source_context or {}),
            "resolved_candidate": candidate.model_dump(),
            "quality_score": round(gate_score, 4),
        }

    async def _context_for_job(self, job: AigcVideoJob):
        episode = await self.db.get(Episode, job.episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")
        highlight_id = (job.source_context or {}).get("highlight_id")
        highlight = await self.db.get(Highlight, highlight_id) if highlight_id else None
        return await build_generation_context(
            self.db,
            episode=episode,
            ts_in_video=job.ts_in_video,
            trigger_type=job.trigger_type,
            highlight=highlight,
            story_thread_id=(job.source_context or {}).get("story_thread_id"),
        )

    def _intent_for_job(self, job: AigcVideoJob, context):
        raw = (job.source_context or {}).get("insert_intent")
        if isinstance(raw, dict):
            try:
                from .schemas import VideoInsertIntent

                return VideoInsertIntent.model_validate(raw)
            except Exception:
                pass
        return plan_video_intent(context=context, user_prompt="")

    async def _materialize_provider_output(self, job: AigcVideoJob, output_video_url: str) -> Path:
        generated_root = Path(settings.generated_media_root).resolve()
        if output_video_url.startswith("/"):
            local = output_video_url.removeprefix("/generated/").lstrip("/")
            path = generated_root / local
            if not path.is_file():
                raise RuntimeError(f"本地候选视频不存在: {path}")
            return path
        target = generated_root / "aigc" / "source" / f"{job.id}.mp4"
        provider = self._provider()
        await provider.download(output_video_url, target)
        return target

    def _local_provider_source_url(self, job: AigcVideoJob) -> str:
        generated_root = Path(settings.generated_media_root).resolve()
        relative = Path("aigc") / "source" / f"{job.id}.mp4"
        return f"/generated/{relative.as_posix()}" if (generated_root / relative).is_file() else ""

    def _should_submit_real_provider(self) -> bool:
        return settings.aigc_video_real_enabled and self._provider_name() != "mock"

    def _provider_name(self) -> str:
        provider = settings.aigc_video_provider.strip().lower()
        if provider in {"jimeng", "seedance", "ark_video"}:
            return provider
        if provider == "mock":
            return "mock"
        return "seedance" if settings.aigc_video_real_enabled else "mock"

    def _provider(self):
        return MockVideoGenerationProvider() if self._provider_name() == "mock" else JimengVideoGenerationProvider()

    def _set_job_status(
        self,
        job: AigcVideoJob,
        status: str,
        progress: float,
        detail: str,
    ) -> None:
        source_context = dict(job.source_context or {})
        history = list(source_context.get("status_history") or [])
        event = self._status_event(status, progress, detail)
        if history and history[-1].get("status") == status:
            history[-1] = event
        else:
            history.append(event)
        source_context["status_history"] = history
        job.source_context = source_context
        job.status = status
        job.progress = max(0.0, min(float(progress), 1.0))

    def _history_contains(self, job: AigcVideoJob, status: str) -> bool:
        return any(
            item.get("status") == status
            for item in ((job.source_context or {}).get("status_history") or [])
            if isinstance(item, dict)
        )

    def _status_event(self, status: str, progress: float, detail: str) -> dict:
        return {
            "status": status,
            "progress": round(max(0.0, min(float(progress), 1.0)), 4),
            "detail": detail,
            "at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        }

    async def _get_by_source_key(self, key: str) -> AigcVideoJob | None:
        result = await self.db.execute(select(AigcVideoJob).limit(100))
        for job in result.scalars().all():
            if (job.source_context or {}).get("idempotency_key") == key:
                return job
        return None

    def _job_id(self, payload: AigcVideoJobCreateIn) -> str:
        basis = payload.idempotency_key or f"{payload.episode_id}:{payload.user_id}:{payload.ts_in_video}:{time.time_ns()}"
        digest = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:10]
        return f"aigc_{payload.episode_id}_{int(payload.ts_in_video * 1000)}_{digest}"

    def _boost_point_id(self, *, episode_id: str, trigger_ts: float) -> str:
        basis = f"{episode_id}:{trigger_ts:.3f}"
        digest = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:10]
        return f"boost_{episode_id}_{int(trigger_ts * 1000)}_{digest}"

    async def _quality_score_for_job(self, job: AigcVideoJob) -> float:
        source_score = (job.source_context or {}).get("quality_score")
        if isinstance(source_score, (int, float)):
            return float(source_score)
        result = await self.db.execute(
            select(AigcQualityCheck)
            .where(AigcQualityCheck.job_id == job.id)
            .order_by(AigcQualityCheck.created_at.desc())
            .limit(1)
        )
        check = result.scalars().first()
        return float(check.final_score) if check else 0.0

    def _source_job_summary(self, job: AigcVideoJob | None) -> dict:
        if job is None:
            return {}
        return {
            "job_id": job.id,
            "status": job.status,
            "provider": job.provider,
            "provider_job_id": job.provider_job_id,
            "output_video_url": job.output_video_url,
        }

    def _to_out(self, job: AigcVideoJob) -> AigcVideoJobOut:
        source_context = job.source_context or {}
        return AigcVideoJobOut(
            job_id=job.id,
            episode_id=job.episode_id,
            user_id=job.user_id,
            status=job.status,
            progress=job.progress,
            trigger_type=job.trigger_type,
            prompt=job.prompt,
            provider=job.provider,
            provider_job_id=job.provider_job_id,
            output_video_url=job.output_video_url,
            hls_url=job.hls_url,
            cover_url=job.cover_url,
            duration=job.duration,
            resume_at=job.resume_at,
            error_message=job.error_message,
            quality_score=float(source_context.get("quality_score") or 0.0),
            quality_decision=str(source_context.get("quality_decision") or ""),
            status_history=list(source_context.get("status_history") or []),
            review_frames=list(source_context.get("review_frames") or []),
            poll_url=f"/api/aigc-video/jobs/{job.id}",
            created_at=job.created_at,
            updated_at=job.updated_at,
        )

    def _to_boost_out(self, point: AigcBoostPoint) -> AigcBoostPointOut:
        return AigcBoostPointOut(
            id=point.id,
            episode_id=point.episode_id,
            trigger_ts=point.trigger_ts,
            resume_at=point.resume_at,
            title=point.title,
            prompt=point.prompt,
            provider=point.provider,
            source_job_id=point.source_job_id,
            output_video_url=point.output_video_url,
            hls_url=point.hls_url,
            cover_url=point.cover_url,
            duration=point.duration,
            quality_score=point.quality_score,
            status=point.status,
            created_at=point.created_at,
            updated_at=point.updated_at,
        )
