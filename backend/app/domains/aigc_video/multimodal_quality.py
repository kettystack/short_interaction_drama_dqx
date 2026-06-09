from __future__ import annotations

import base64
import json
import re
from pathlib import Path
from typing import Any

import httpx

from ...config import settings
from .schemas import AigcGenerationContext, MultimodalQualityResult, VideoInsertIntent

_ARK_CHAT_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"


async def evaluate_generated_video(
    *,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    source_first_frame: Path,
    source_resume_frame: Path | None,
    generated_frames: list[Path],
) -> MultimodalQualityResult:
    endpoint = settings.aigc_video_multimodal_endpoint.strip() or settings.doubao_endpoint.strip()
    api_key = settings.aigc_video_multimodal_api_key.strip() or settings.doubao_api_key.strip()
    if not settings.aigc_video_multimodal_enabled:
        return _unavailable("多模态质量评估未启用")
    if not api_key or not endpoint:
        return _unavailable("多模态质量评估模型未配置")
    if not source_first_frame.is_file() or not generated_frames:
        return _unavailable("缺少首帧或生成视频抽帧")

    content: list[dict[str, Any]] = [
        {
            "type": "text",
            "text": (
                "请评估这段短剧 AI 插片。第一张是正片输入首帧，后面是生成视频的开头、中间、结尾抽帧。"
                "若提供了正片续播参考帧，它只用于判断场景衔接，不要求人物始终与该参考帧相同。"
            ),
        },
        {"type": "text", "text": "[正片输入首帧]"},
        _image_item(source_first_frame),
    ]
    if source_resume_frame and source_resume_frame.is_file():
        content.extend(
            [
                {"type": "text", "text": "[正片续播参考帧]"},
                _image_item(source_resume_frame),
            ]
        )
    for index, frame in enumerate(generated_frames):
        content.extend(
            [
                {"type": "text", "text": f"[生成视频抽帧 {index + 1}]"},
                _image_item(frame),
            ]
        )
    content.append(
        {
            "type": "text",
            "text": (
                f"剧情：{context.episode_title}；触发类型：{intent.trigger_type}；"
                f"目标动作：{intent.action}；目标情绪：{intent.emotion}；"
                f"附近剧情：{context.highlight_text or context.nearby_events[:2]}。"
            ),
        }
    )
    system = (
        "你是短剧 AIGC 插片质检员。必须严格比较正片首帧与生成抽帧，不能只依据提示词。"
        "重点识别：人物是否变成陌生人或不同国籍/年龄/性别，服装和场景是否突变，"
        "动作是否符合触发意图，是否有肢体畸变、画面崩坏、文字水印、低俗暴力、敏感内容或明显版权角色。"
        "只输出 JSON 对象，字段为："
        "character_continuity,scene_continuity,action_match,visual_quality,safety_score,copyright_risk"
        "（均为0到1）；obvious_mismatch（布尔）；decision（pass/review/reject）；reasons（中文字符串数组）。"
        "人物明显变化、首帧未被延续、出现完全无关场景时，obvious_mismatch 必须为 true 且不可 pass。"
    )
    payload = {
        "model": endpoint,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": content},
        ],
        "temperature": 0.1,
    }
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post(
                _ARK_CHAT_URL,
                json=payload,
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
            )
            response.raise_for_status()
            response_payload = response.json()
        raw_text = response_payload["choices"][0]["message"]["content"]
        parsed = _parse_json_object(raw_text)
        return MultimodalQualityResult(
            available=True,
            decision=_decision(parsed.get("decision")),
            character_continuity=_score(parsed.get("character_continuity")),
            scene_continuity=_score(parsed.get("scene_continuity")),
            action_match=_score(parsed.get("action_match")),
            visual_quality=_score(parsed.get("visual_quality")),
            safety_score=_score(parsed.get("safety_score")),
            copyright_risk=_score(parsed.get("copyright_risk")),
            obvious_mismatch=bool(parsed.get("obvious_mismatch")),
            reasons=[str(item)[:160] for item in (parsed.get("reasons") or [])][:8],
            raw={"model": endpoint, "response": parsed},
        )
    except Exception as exc:
        return _unavailable(f"多模态质量评估失败：{str(exc)[:240]}")


def _image_item(path: Path) -> dict[str, Any]:
    suffix = path.suffix.lower().lstrip(".")
    image_format = "jpeg" if suffix in {"jpg", "jpeg"} else suffix
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return {
        "type": "image_url",
        "image_url": {"url": f"data:image/{image_format};base64,{encoded}"},
    }


def _parse_json_object(text: Any) -> dict:
    clean = str(text or "").strip()
    clean = re.sub(r"^```(?:json)?", "", clean).rstrip("`").strip()
    match = re.search(r"\{.*\}", clean, re.S)
    if match:
        clean = match.group(0)
    parsed = json.loads(clean)
    if not isinstance(parsed, dict):
        raise ValueError("质量评估结果不是 JSON 对象")
    return parsed


def _score(value: Any) -> float:
    try:
        return max(0.0, min(float(value), 1.0))
    except (TypeError, ValueError):
        return 0.0


def _decision(value: Any) -> str:
    clean = str(value or "review").lower()
    return clean if clean in {"pass", "review", "reject"} else "review"


def _unavailable(reason: str) -> MultimodalQualityResult:
    return MultimodalQualityResult(
        available=False,
        decision="review",
        reasons=[reason],
        raw={"error": reason},
    )
