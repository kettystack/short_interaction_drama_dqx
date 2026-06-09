from __future__ import annotations

import hashlib
import time
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from ...config import settings
from ...models import ModelCallLog
from ...services.ai_service import chat_completion, chat_model_name, chat_provider_name


def rough_token_count(text: str) -> int:
    return max(1, len(text) // 3)


async def tracked_chat_completion(
    db: AsyncSession,
    messages: list[dict],
    *,
    scene: str,
    user_id: str = "system",
    episode_id: str = "",
    temperature: float = 0.7,
    max_tokens: int | None = None,
    response_format: dict[str, Any] | None = None,
) -> str:
    started = time.perf_counter()
    status = "ok"
    content = ""
    try:
        content = await chat_completion(
            messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format=response_format,
        )
        return content
    except Exception:
        status = "failed"
        raise
    finally:
        latency_ms = int((time.perf_counter() - started) * 1000)
        prompt_text = "\n".join(str(item.get("content", "")) for item in messages)
        prompt_tokens = rough_token_count(prompt_text)
        completion_tokens = rough_token_count(content) if content else 0
        call_id = hashlib.sha1(
            f"{scene}:{user_id}:{episode_id}:{time.time_ns()}".encode("utf-8")
        ).hexdigest()[:16]
        db.add(
            ModelCallLog(
                id=f"mcall_{call_id}",
                provider=chat_provider_name(),
                model=chat_model_name() or settings.doubao_endpoint,
                scene=scene,
                user_id=user_id,
                episode_id=episode_id,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                latency_ms=latency_ms,
                status=status,
            )
        )
        await db.commit()
