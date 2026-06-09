from __future__ import annotations

from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import AigcQualityCheck
from .multimodal_quality import evaluate_generated_video
from .schemas import AigcGenerationContext, ClipCandidate, QualityGateResult, VideoInsertIntent


async def validate_clip(
    db: AsyncSession,
    *,
    job_id: str,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    candidate: ClipCandidate,
) -> QualityGateResult:
    result = _score_candidate(context=context, intent=intent, candidate=candidate)
    db.add(
        AigcQualityCheck(
            job_id=job_id,
            candidate_url=candidate.clip_url,
            context_score=result.context_score,
            character_score=result.character_score,
            action_score=result.action_score,
            style_score=result.style_score,
            final_score=result.score,
            final_decision=result.decision,
            reasons=result.reasons,
            raw={
                "candidate": candidate.model_dump(),
                "intent": intent.model_dump(),
                "context": {
                    "episode_id": context.episode_id,
                    "ts_in_video": context.ts_in_video,
                    "resume_at": context.resume_at,
                    "highlight_id": context.highlight_id,
                },
            },
        )
    )
    await db.flush()
    return result


async def validate_provider_clip(
    db: AsyncSession,
    *,
    job_id: str,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    candidate: ClipCandidate,
    source_first_frame: Path,
    source_resume_frame: Path | None,
    generated_frames: list[Path],
    technical: dict,
) -> QualityGateResult:
    visual = await evaluate_generated_video(
        context=context,
        intent=intent,
        source_first_frame=source_first_frame,
        source_resume_frame=source_resume_frame,
        generated_frames=generated_frames,
    )
    technical_score = float(technical.get("technical_score") or 0.0)
    multimodal_score = (
        visual.character_continuity * 0.28
        + visual.scene_continuity * 0.18
        + visual.action_match * 0.16
        + visual.visual_quality * 0.16
        + visual.safety_score * 0.22
    )
    final_score = technical_score * 0.2 + multimodal_score * 0.8
    reasons = [
        *[str(item) for item in technical.get("technical_reasons") or []],
        *visual.reasons,
    ]
    first_frame_ssim = float(technical.get("first_frame_ssim") or 0.0)
    if first_frame_ssim:
        reasons.insert(0, f"正片首帧相似度 SSIM={first_frame_ssim:.3f}")

    if first_frame_ssim and first_frame_ssim < 0.55:
        decision = "reject"
        reasons.append("生成视频开头未延续正片首帧")
    elif first_frame_ssim and first_frame_ssim < settings.aigc_video_first_frame_min_ssim:
        decision = "review"
        reasons.append("首帧相似度不足，必须人工审核")
    elif not visual.available:
        decision = "review"
        reasons.append("视觉评估不可用，禁止自动发布")
    elif visual.obvious_mismatch or visual.decision == "reject":
        decision = "reject"
        reasons.append("人物或场景存在明显错配")
    elif visual.safety_score < 0.5:
        decision = "reject"
        reasons.append("内容安全分过低")
    elif (
        not bool(technical.get("technical_pass"))
        or visual.safety_score < 0.8
        or visual.copyright_risk > 0.7
        or visual.decision == "review"
    ):
        decision = "review"
        reasons.append("需要人工复核技术规格、内容安全或版权风险")
    elif final_score >= settings.aigc_video_auto_publish_min_score:
        decision = "pass"
        reasons.append(f"综合质量分 {final_score:.2f} 达到自动发布阈值")
    elif final_score >= settings.aigc_video_review_min_score:
        decision = "review"
        reasons.append(f"综合质量分 {final_score:.2f} 进入人工审核区间")
    else:
        decision = "reject"
        reasons.append(f"综合质量分 {final_score:.2f} 低于最低阈值")

    result = QualityGateResult(
        decision=decision,
        score=final_score,
        context_score=visual.scene_continuity,
        character_score=visual.character_continuity,
        action_score=visual.action_match,
        style_score=visual.visual_quality,
        safety_score=visual.safety_score,
        technical_score=technical_score,
        multimodal_score=multimodal_score,
        requires_human_review=decision == "review",
        reasons=reasons,
        raw={
            "technical": technical,
            "multimodal": visual.model_dump(),
            "candidate": candidate.model_dump(),
        },
    )
    db.add(
        AigcQualityCheck(
            job_id=job_id,
            candidate_url=candidate.clip_url,
            context_score=result.context_score,
            character_score=result.character_score,
            action_score=result.action_score,
            style_score=result.style_score,
            final_score=result.score,
            final_decision=result.decision,
            reasons=result.reasons,
            raw=result.raw,
        )
    )
    await db.flush()
    return result


def _score_candidate(
    *,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    candidate: ClipCandidate,
) -> QualityGateResult:
    reasons: list[str] = []
    context_score = 0.0
    if candidate.episode_id == context.episode_id:
        context_score += 0.55
        reasons.append("episode_id 匹配")
    else:
        reasons.append("episode_id 不匹配")
    if candidate.drama_id and candidate.drama_id == context.drama_id:
        context_score += 0.2
        reasons.append("drama_id 匹配")
    if candidate.score > 0:
        context_score += min(candidate.score, 1.0) * 0.25

    action_score = 0.35
    haystack = " ".join(candidate.match_reasons).lower()
    for token in [intent.action, intent.emotion, intent.trigger_type]:
        if token and token.lower() in haystack:
            action_score += 0.12
    if candidate.source == "clip_asset":
        action_score += 0.18
        reasons.append("使用 clip_assets，可运营素材")
    elif candidate.source == "provider_generated":
        action_score += 0.16
        reasons.append("使用首尾帧约束生成素材")
    elif candidate.source == "branch_fallback":
        action_score -= 0.08
        reasons.append("branch fallback 来源，仅作演示兜底")

    character_score = 0.65 if context.first_frame_url and context.last_frame_url else 0.45
    style_score = 0.7 if 2.0 <= (candidate.duration or intent.duration_seconds) <= 15.5 else 0.45
    if candidate.source == "branch_fallback" and (candidate.duration or 0) > 18:
        style_score -= 0.2
        reasons.append("branch 片段时长过长，不适合加速包")

    final_score = (
        context_score * 0.42
        + character_score * 0.22
        + action_score * 0.22
        + style_score * 0.14
    )
    min_score = settings.aigc_video_quality_min_score
    if candidate.source == "branch_fallback":
        min_score += 0.08
    decision = "pass" if final_score >= min_score else "reject"
    if decision == "reject":
        reasons.append(f"质量分 {final_score:.2f} 低于阈值 {min_score:.2f}")
    else:
        reasons.append(f"质量分 {final_score:.2f} 通过")

    return QualityGateResult(
        decision=decision,
        score=final_score,
        context_score=min(context_score, 1.0),
        character_score=max(min(character_score, 1.0), 0.0),
        action_score=max(min(action_score, 1.0), 0.0),
        style_score=max(min(style_score, 1.0), 0.0),
        reasons=reasons,
    )
