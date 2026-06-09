from __future__ import annotations

import hashlib
import json

from ...config import settings
from .schemas import BranchOptionPlan, BranchVideoContext


def build_variant_cache_key(
    context: BranchVideoContext,
    option: BranchOptionPlan,
    *,
    duration: float,
    prompt_version: str,
) -> str:
    payload = {
        "episode_id": context.episode_id,
        "trigger_source": context.trigger_source,
        "trigger_ts": round(context.trigger_ts, 3),
        "source_frame_url": context.source_frame_url,
        "manual_context": context.manual_context,
        "option": option.model_dump(mode="json"),
        "model": settings.aigc_video_model,
        "prompt_version": prompt_version,
        "duration": round(duration, 2),
    }
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
