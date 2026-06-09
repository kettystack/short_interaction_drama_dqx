from __future__ import annotations

import hashlib
import json
from datetime import datetime
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ...config import settings
from ...models import (
    Branch,
    BranchFork,
    BranchPlaybackEvent,
    BranchVideoVariant,
    Episode,
    Highlight,
    PersonalizedBranchOption,
    PersonalizedBranchSession,
)
from ..security.moderation import ModerationService
from ..security.schemas import CurrentUser
from .context_builder import build_branch_context
from .manual_context import list_manual_branch_points
from .option_planner import (
    plan_branch_options,
    plan_from_custom_prompt,
    plans_from_configured_branches,
)
from .repository import BranchVideoRepository
from .schemas import (
    BranchOptionPlan,
    BranchPlaybackEventIn,
    BranchPlaybackTicket,
    BranchVideoCustomOptionIn,
    BranchVideoOptionOut,
    BranchVideoPrewarmOut,
    BranchVideoSelectionOut,
    BranchVideoSelectIn,
    BranchVideoSessionCreateIn,
    BranchVideoSessionOut,
)
from .worker import BranchVideoWorker


class BranchVideoService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.repo = BranchVideoRepository(db)
        self.worker = BranchVideoWorker(db)

    async def ensure_episode_sessions(
        self,
        *,
        episode_id: str,
        user: CurrentUser,
    ) -> list[BranchVideoSessionOut]:
        if not settings.branch_video_enabled:
            return []
        episode = await self.db.get(Episode, episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")
        await self._create_detected_sessions(episode, user)
        sessions = await self.repo.list_sessions(
            episode_id=episode_id,
            user_id=user.user_id,
        )
        manual_points = list_manual_branch_points(
            drama_id=episode.drama_id,
            episode_id=episode.id,
        )
        sessions = self._select_current_sessions(sessions, manual_points)
        result = []
        for session in sessions:
            result.append(await self.get_session(session.id, user=user, refresh=False))
        return result

    async def create_session(
        self,
        payload: BranchVideoSessionCreateIn,
        *,
        user: CurrentUser,
    ) -> BranchVideoSessionOut:
        episode = await self.db.get(Episode, payload.episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")
        fork = await self.db.get(BranchFork, payload.fork_id) if payload.fork_id else None
        highlight = await self.db.get(Highlight, payload.highlight_id) if payload.highlight_id else None
        resume_at = self._resume_at(episode, payload.ts_in_video)
        session = await self._create_session_record(
            episode=episode,
            user=user,
            trigger_source=payload.trigger_source,
            trigger_ts=payload.ts_in_video,
            resume_at=resume_at,
            fork=fork,
            highlight=highlight,
            option_count=payload.option_count,
            target_duration=payload.target_duration,
        )
        return await self.get_session(session.id, user=user, refresh=False)

    async def get_session(
        self,
        session_id: str,
        *,
        user: CurrentUser,
        refresh: bool = True,
    ) -> BranchVideoSessionOut:
        session = await self._require_session(session_id, user)
        options = await self.repo.list_options(session.id)
        if refresh:
            for option in options:
                await self.worker.sync_option(option)
            options = await self.repo.list_options(session.id)
        session.status = self._session_status(options)
        session.updated_at = datetime.utcnow()
        await self.db.commit()
        return await self._to_session_out(session, options)

    async def prewarm(
        self,
        session_id: str,
        *,
        user: CurrentUser,
    ) -> BranchVideoPrewarmOut:
        session = await self._require_session(session_id, user)
        options = await self.repo.list_options(session.id)
        target_duration = float(
            (session.context_snapshot or {}).get("target_duration")
            or settings.branch_video_target_duration_seconds
        )
        submitted: list[str] = []
        for option in options:
            variant = await self.repo.published_variant(option.id)
            if variant is not None:
                option.status = "ready"
                continue
            if option.status in {"planned", "failed"}:
                try:
                    await self.worker.generate_option(
                        session=session,
                        option=option,
                        user=user,
                        target_duration=target_duration,
                    )
                    submitted.append(option.id)
                except Exception as exc:
                    option.status = "failed"
                    option.error_message = str(exc)[:500]
                    await self.db.commit()
        out = await self.get_session(session.id, user=user, refresh=True)
        return BranchVideoPrewarmOut(
            session_id=session.id,
            status=out.status,
            submitted_option_ids=submitted,
            session=out,
        )

    async def create_custom_option(
        self,
        session_id: str,
        payload: BranchVideoCustomOptionIn,
        *,
        user: CurrentUser,
    ) -> BranchVideoSessionOut:
        session = await self._require_session(session_id, user)
        moderation = await ModerationService(self.db).check_text(
            payload.prompt,
            scene="branch_video_custom_prompt",
            user_id=user.user_id,
        )
        if moderation.decision != "allow" and moderation.risk_score >= 0.85:
            raise HTTPException(400, "prompt needs review before generation")
        options = await self.repo.list_options(session.id)
        plan = plan_from_custom_prompt(payload.prompt, order_idx=len(options))
        option = self._new_option(session.id, plan, order_idx=len(options))
        option.user_prompt = payload.prompt
        self.db.add(option)
        await self.db.commit()
        try:
            await self.worker.generate_option(
                session=session,
                option=option,
                user=user,
                target_duration=payload.target_duration,
            )
        except Exception as exc:
            option.status = "failed"
            option.error_message = str(exc)[:500]
            await self.db.commit()
        return await self.get_session(session.id, user=user, refresh=True)

    async def select_option(
        self,
        session_id: str,
        payload: BranchVideoSelectIn,
        *,
        user: CurrentUser,
    ) -> BranchVideoSelectionOut:
        session = await self._require_session(session_id, user)
        option = await self.repo.get_option(payload.option_id)
        if option is None or option.session_id != session.id:
            raise HTTPException(404, "branch option not found")
        variant = await self.repo.published_variant(option.id)
        if variant is None:
            if option.status in {"planned", "failed"}:
                target_duration = float(
                    (session.context_snapshot or {}).get("target_duration")
                    or settings.branch_video_target_duration_seconds
                )
                try:
                    variant = await self.worker.generate_option(
                        session=session,
                        option=option,
                        user=user,
                        target_duration=target_duration,
                    )
                except Exception as exc:
                    option.status = "failed"
                    option.error_message = str(exc)[:500]
                    await self.db.commit()
            else:
                await self.worker.sync_option(option)
            variant = await self.repo.published_variant(option.id)

        await self._record_select_once(session, option, variant, payload, user)
        option_out = await self._to_option_out(option)
        if variant is None or not variant.output_video_url:
            return BranchVideoSelectionOut(status=option.status, option=option_out)

        episode = await self.db.get(Episode, session.episode_id)
        if episode is None:
            raise HTTPException(404, "episode not found")
        story_text = self._story_text(option)
        return BranchVideoSelectionOut(
            status="ready",
            option=option_out,
            playback_ticket=BranchPlaybackTicket(
                session_id=session.id,
                option_id=option.id,
                variant_id=variant.id,
                video_url=variant.output_video_url,
                duration=variant.duration,
                main_video_url=episode.video_url,
                resume_at=session.resume_at,
                label=option.label,
                story_text=story_text,
            ),
        )

    async def record_event(
        self,
        payload: BranchPlaybackEventIn,
        *,
        user: CurrentUser,
    ) -> dict:
        session = await self._require_session(payload.session_id, user)
        if payload.client_event_id:
            existing = await self.db.execute(
                select(BranchPlaybackEvent).where(
                    BranchPlaybackEvent.client_event_id == payload.client_event_id
                )
            )
            if existing.scalars().first():
                return {"recorded": False, "duplicate": True}
        event = BranchPlaybackEvent(
            session_id=session.id,
            option_id=payload.option_id,
            variant_id=payload.variant_id,
            user_id=user.user_id,
            event_type=payload.event_type,
            ts_in_main_video=payload.ts_in_main_video,
            clip_position=payload.clip_position,
            client_event_id=payload.client_event_id,
            payload_json=payload.payload,
        )
        self.db.add(event)
        if payload.event_type == "play_complete":
            session.status = "completed"
        await self.db.commit()
        return {"recorded": True, "event_type": payload.event_type}

    async def _create_detected_sessions(
        self,
        episode: Episode,
        user: CurrentUser,
    ) -> None:
        forks_result = await self.db.execute(
            select(BranchFork)
            .where(BranchFork.episode_id == episode.id)
            .options(selectinload(BranchFork.branches))
            .order_by(BranchFork.ts_in_video)
        )
        forks = list(forks_result.scalars().all())
        highlights_result = await self.db.execute(
            select(Highlight)
            .where(Highlight.episode_id == episode.id)
            .order_by(Highlight.ts_start)
        )
        highlights = list(highlights_result.scalars().all())
        detected_duration = self._episode_duration(episode, highlights)
        if episode.duration <= 1 and detected_duration > 1:
            episode.duration = detected_duration
            await self.db.commit()
        candidates: list[tuple[str, float, BranchFork | None, Highlight | None]] = []
        content_slots = max(settings.branch_video_max_sessions_per_episode - 1, 1)
        tail_ts = max(detected_duration - 8.0, 10.0)
        manual_points = list_manual_branch_points(
            drama_id=episode.drama_id,
            episode_id=episode.id,
        )
        if manual_points:
            for point in manual_points[: settings.branch_video_max_sessions_per_episode]:
                source = str(point.get("trigger_source") or "highlight")
                trigger_ts = max(float(point.get("trigger_ts") or 0.0), 0.0)
                force_trigger_ts = bool(point.get("force_trigger_ts"))
                fork = (
                    min(forks, key=lambda item: abs(item.ts_in_video - trigger_ts), default=None)
                    if source == "fork"
                    else None
                )
                highlight = (
                    min(
                        highlights,
                        key=lambda item: abs(
                            max(item.ts_end - 0.5, item.ts_start) - trigger_ts
                        ),
                        default=None,
                    )
                    if source == "highlight"
                    else None
                )
                if fork and abs(fork.ts_in_video - trigger_ts) > 3:
                    fork = None
                if highlight and abs(
                    max(highlight.ts_end - 0.5, highlight.ts_start) - trigger_ts
                ) > 3:
                    highlight = None
                if not force_trigger_ts:
                    if fork is not None:
                        trigger_ts = fork.ts_in_video
                    elif highlight is not None:
                        trigger_ts = max(highlight.ts_end - 0.5, highlight.ts_start)
                    elif source == "episode_tail" and abs(tail_ts - trigger_ts) <= 3:
                        trigger_ts = tail_ts
                candidates.append((source, trigger_ts, fork, highlight))
        else:
            for fork in forks[:content_slots]:
                candidates.append(("fork", fork.ts_in_video, fork, None))

            critical = [
                item
                for item in highlights
                if item.intensity >= settings.branch_video_highlight_min_intensity
                and str((item.raw or {}).get("source") or "") != "ambient"
                and item.type not in {"搞笑", "搞笑包袱", "年龄反差梗"}
            ]
            critical.sort(key=lambda item: (-item.intensity, item.ts_end))
            if len(candidates) < content_slots:
                for highlight in critical:
                    trigger_ts = max(highlight.ts_end - 0.5, highlight.ts_start)
                    if abs(tail_ts - trigger_ts) < 25:
                        continue
                    if any(abs(trigger_ts - existing[1]) < 35 for existing in candidates):
                        continue
                    candidates.append(("highlight", trigger_ts, None, highlight))
                    if len(candidates) >= content_slots:
                        break

        if detected_duration > 30 and not any(
            source == "episode_tail" or abs(trigger_ts - tail_ts) < 3
            for source, trigger_ts, _, _ in candidates
        ):
            candidates.append(("episode_tail", tail_ts, None, None))
        if not candidates:
            tail_ts = max((episode.duration or 0) - 8.0, 10.0)
            candidates.append(("episode_tail", tail_ts, None, None))

        candidates = sorted(candidates, key=lambda item: item[1])[
            : settings.branch_video_max_sessions_per_episode
        ]
        for source, trigger_ts, fork, highlight in candidates:
            await self._create_session_record(
                episode=episode,
                user=user,
                trigger_source=source,
                trigger_ts=trigger_ts,
                resume_at=self._resume_at(episode, trigger_ts),
                fork=fork,
                highlight=highlight,
                option_count=3,
                target_duration=settings.branch_video_target_duration_seconds,
            )

    async def _create_session_record(
        self,
        *,
        episode: Episode,
        user: CurrentUser,
        trigger_source: str,
        trigger_ts: float,
        resume_at: float,
        fork: BranchFork | None,
        highlight: Highlight | None,
        option_count: int,
        target_duration: float,
    ) -> PersonalizedBranchSession:
        session_id = self._session_id(
            episode.id,
            user.user_id,
            trigger_source,
            trigger_ts,
        )
        existing = await self.repo.get_session(session_id)
        if existing:
            return existing
        context = await build_branch_context(
            self.db,
            episode=episode,
            trigger_source=trigger_source,
            trigger_ts=trigger_ts,
            resume_at=resume_at,
            fork=fork,
            highlight=highlight,
            user_id=user.user_id,
        )
        if fork:
            branches = sorted(fork.branches, key=lambda item: item.order_idx)
            plans = plans_from_configured_branches(context, branches)
            plans.question = fork.prompt_text or plans.question
        else:
            plans = await plan_branch_options(
                self.db,
                context,
                option_count=option_count,
                user_id=user.user_id,
            )
        snapshot = context.model_dump(mode="json")
        snapshot["target_duration"] = target_duration
        session = PersonalizedBranchSession(
            id=session_id,
            episode_id=episode.id,
            fork_id=fork.id if fork else None,
            highlight_id=highlight.id if highlight else None,
            user_id=user.user_id,
            trigger_source=trigger_source,
            trigger_ts=max(trigger_ts, 0.0),
            resume_at=resume_at,
            question=plans.question,
            context_snapshot=snapshot,
            status="planned",
        )
        self.db.add(session)
        await self.db.flush()
        for index, plan in enumerate(plans.options[:option_count]):
            self.db.add(self._new_option(session.id, plan, order_idx=index))
        await self.db.commit()
        await self.db.refresh(session)
        return session

    def _new_option(
        self,
        session_id: str,
        plan: BranchOptionPlan,
        *,
        order_idx: int,
    ) -> PersonalizedBranchOption:
        digest = hashlib.sha1(
            f"{session_id}:{plan.option_key}:{plan.label}".encode("utf-8")
        ).hexdigest()[:12]
        return PersonalizedBranchOption(
            id=f"pbo_{digest}",
            session_id=session_id,
            option_key=plan.option_key,
            label=plan.label,
            description=plan.description,
            intent=plan.model_dump(mode="json"),
            status="planned",
            order_idx=order_idx,
        )

    async def _require_session(
        self,
        session_id: str,
        user: CurrentUser,
    ) -> PersonalizedBranchSession:
        session = await self.repo.get_session(session_id)
        if session is None:
            raise HTTPException(404, "branch video session not found")
        if not user.is_admin and session.user_id not in {user.user_id, "anon"}:
            raise HTTPException(403, "cannot access this branch session")
        return session

    async def _to_session_out(
        self,
        session: PersonalizedBranchSession,
        options: list[PersonalizedBranchOption],
    ) -> BranchVideoSessionOut:
        return BranchVideoSessionOut(
            session_id=session.id,
            episode_id=session.episode_id,
            fork_id=session.fork_id,
            highlight_id=session.highlight_id,
            trigger_source=session.trigger_source,
            trigger_ts=session.trigger_ts,
            resume_at=session.resume_at,
            question=session.question,
            status=session.status,
            options=[await self._to_option_out(option) for option in options],
            created_at=session.created_at,
            updated_at=session.updated_at,
        )

    async def _to_option_out(
        self,
        option: PersonalizedBranchOption,
    ) -> BranchVideoOptionOut:
        variant = await self.repo.published_variant(option.id)
        latest = variant or await self.repo.latest_variant(option.id)
        quality = float(latest.quality_score) if latest else 0.0
        return BranchVideoOptionOut(
            id=option.id,
            option_key=option.option_key,
            label=option.label,
            description=option.description,
            intent=option.intent or {},
            status=option.status,
            order_idx=option.order_idx,
            story_text=self._story_text(option),
            video_url=variant.output_video_url if variant else "",
            duration=variant.duration if variant else 0.0,
            quality_score=quality,
            quality_label=f"质检 {round(quality * 100)}" if quality > 0 else "",
            variant_id=variant.id if variant else "",
            error_message=option.error_message,
        )

    async def _record_select_once(
        self,
        session: PersonalizedBranchSession,
        option: PersonalizedBranchOption,
        variant: BranchVideoVariant | None,
        payload: BranchVideoSelectIn,
        user: CurrentUser,
    ) -> None:
        if payload.client_event_id:
            result = await self.db.execute(
                select(BranchPlaybackEvent).where(
                    BranchPlaybackEvent.client_event_id == payload.client_event_id
                )
            )
            if result.scalars().first():
                return
        option.selected_count += 1
        self.db.add(
            BranchPlaybackEvent(
                session_id=session.id,
                option_id=option.id,
                variant_id=variant.id if variant else "",
                user_id=user.user_id,
                event_type="select",
                ts_in_main_video=session.trigger_ts,
                client_event_id=payload.client_event_id,
                payload_json={"status": option.status, "label": option.label},
            )
        )
        await self.db.commit()

    def _session_status(self, options: list[PersonalizedBranchOption]) -> str:
        if not options:
            return "failed"
        statuses = {option.status for option in options}
        ready_count = sum(1 for option in options if option.status == "ready")
        if ready_count == len(options):
            return "ready"
        if ready_count > 0:
            return "partially_ready"
        if statuses <= {"failed"}:
            return "failed"
        if statuses & {
            "submitting",
            "submitted",
            "generating",
            "downloading",
            "transcoding",
            "quality_checking",
            "review_required",
        }:
            return "generating"
        return "planned"

    def _resume_at(self, episode: Episode, trigger_ts: float) -> float:
        target = max(trigger_ts, 0.0) + max(settings.aigc_resume_offset_seconds, 0.0)
        if episode.duration > 1:
            return min(target, max(episode.duration - 0.8, 0.0))
        return target

    @staticmethod
    def _select_current_sessions(
        sessions: list[PersonalizedBranchSession],
        manual_points: list[dict],
    ) -> list[PersonalizedBranchSession]:
        selected = [
            session
            for session in sessions
            if not (session.context_snapshot or {}).get("manual_context")
        ]
        for point in manual_points:
            source = str(point.get("trigger_source") or "highlight")
            trigger_ts = float(point.get("trigger_ts") or 0.0)
            matches = [
                session
                for session in sessions
                if (session.context_snapshot or {}).get("manual_context")
                and session.trigger_source == source
                and abs(session.trigger_ts - trigger_ts) <= 3
            ]
            if not matches:
                continue
            if bool(point.get("force_trigger_ts")):
                preferred = min(
                    matches,
                    key=lambda session: (
                        abs(session.trigger_ts - trigger_ts),
                        session.created_at,
                    ),
                )
            else:
                preferred = min(matches, key=lambda session: session.created_at)
            selected.append(preferred)
        return sorted(
            {session.id: session for session in selected}.values(),
            key=lambda session: session.trigger_ts,
        )

    def _episode_duration(
        self,
        episode: Episode,
        highlights: list[Highlight],
    ) -> float:
        if episode.duration > 1:
            return float(episode.duration)
        path = Path(settings.data_root) / "highlights" / f"{episode.id}.json"
        if path.is_file():
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
                duration = float(payload.get("duration") or 0)
                if duration > 1:
                    return duration
            except (OSError, ValueError, json.JSONDecodeError):
                pass
        if highlights:
            return max(item.ts_end for item in highlights) + 1.0
        return 0.0

    def _story_text(self, option: PersonalizedBranchOption) -> str:
        story = option.story_plan or {}
        beats = [str(item) for item in story.get("beats") or [] if str(item).strip()]
        if beats:
            return "。".join(beats) + "。"
        return str(story.get("premise") or option.description)

    def _session_id(
        self,
        episode_id: str,
        user_id: str,
        trigger_source: str,
        trigger_ts: float,
    ) -> str:
        basis = f"{episode_id}:{user_id}:{trigger_source}:{trigger_ts:.3f}"
        digest = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:12]
        return f"pbs_{episode_id}_{digest}"
