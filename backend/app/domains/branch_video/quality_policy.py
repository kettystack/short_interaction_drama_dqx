from __future__ import annotations

from ...models import AigcVideoJob, BranchVideoVariant, PersonalizedBranchOption


def sync_variant_from_job(
    option: PersonalizedBranchOption,
    variant: BranchVideoVariant,
    job: AigcVideoJob,
) -> None:
    context = job.source_context or {}
    variant.provider = job.provider
    variant.output_video_url = job.output_video_url
    variant.duration = job.duration
    variant.quality_score = float(context.get("quality_score") or 0.0)
    variant.quality_detail = dict(context.get("quality_gate") or {})
    if job.status == "ready" and job.output_video_url:
        variant.review_status = "approved"
        variant.publish_status = "published"
        option.status = "ready"
        option.error_message = ""
    elif job.status == "review_required":
        variant.review_status = "pending"
        variant.publish_status = "draft"
        option.status = "review_required"
        option.error_message = job.error_message
    elif job.status == "failed":
        variant.review_status = "rejected"
        variant.publish_status = "draft"
        option.status = "failed"
        option.error_message = _friendly_error(job.error_message)
    else:
        variant.review_status = "pending"
        variant.publish_status = "draft"
        option.status = job.status or "generating"


def _friendly_error(message: str | None) -> str:
    text = str(message or "")
    if "AccountOverdueError" in text:
        return "视频生成账户余额不足，请充值后重试"
    if "AccessDenied" in text or "PermissionDenied" in text:
        return "视频生成服务尚未开通或当前密钥无权限"
    return text[:500]
