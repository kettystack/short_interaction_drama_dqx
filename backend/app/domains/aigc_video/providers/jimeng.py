from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import httpx

from ....config import settings
from ..media_uploader import resolve_provider_image
from ..schemas import ProviderJob, ProviderJobStatus, VideoGenerationRequest


class JimengVideoGenerationProvider:
    """Volcengine Ark/Seedance compatible video generation adapter.

    The adapter is intentionally conservative: it supports first-frame and
    first-last-frame image-to-video requests, but the service decides whether a
    generated candidate is allowed to play.
    """

    def __init__(self) -> None:
        self.api_key = settings.doubao_api_key
        self.model = settings.aigc_video_endpoint_id.strip() or settings.aigc_video_model
        self.endpoint = settings.aigc_video_task_endpoint.rstrip("/")

    async def submit(self, request: VideoGenerationRequest) -> ProviderJob:
        if not self.api_key:
            raise RuntimeError("DOUBAO_API_KEY 未配置，无法提交真实视频生成")
        duration = max(
            2,
            min(
                int(round(request.duration)),
                int(settings.aigc_video_provider_max_duration_seconds),
                15,
            ),
        )
        content = _build_content(request)
        body: dict[str, Any] = {
            "model": self.model,
            "content": content,
            "duration": duration,
            "ratio": request.ratio,
            "resolution": settings.aigc_video_resolution,
            "generate_audio": settings.aigc_video_generate_audio,
            "seed": _seed_for_request(request),
            "watermark": settings.aigc_video_watermark,
            "camera_fixed": settings.aigc_video_camera_fixed,
            "return_last_frame": True,
        }
        async with httpx.AsyncClient(timeout=30) as client:
            res = await client.post(
                self.endpoint,
                json=body,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}",
                },
            )
            _raise_for_status(res, scene="提交视频生成任务")
            payload = res.json()
        task_id = _pick(payload, "id", "task_id", "provider_job_id")
        if not task_id and isinstance(payload.get("data"), dict):
            task_id = _pick(payload["data"], "id", "task_id", "provider_job_id")
        if not task_id:
            raise RuntimeError(f"视频生成提交失败，返回缺少 task id: {_safe_payload(payload)}")
        status = _normalize_status(_pick(payload, "status") or _pick(payload.get("data") or {}, "status"))
        return ProviderJob(
            provider_job_id=str(task_id),
            status=status or "submitted",
            progress=float(_pick(payload, "progress") or 0.05),
            output_video_url=_extract_video_url(payload),
            duration=float(_pick(payload, "duration") or request.duration),
            cover_url=str(_pick(payload, "cover_url", "cover") or ""),
        )

    async def poll(self, provider_job_id: str) -> ProviderJobStatus:
        if not self.api_key:
            raise RuntimeError("DOUBAO_API_KEY 未配置，无法查询真实视频生成")
        url = f"{self.endpoint}/{provider_job_id}"
        async with httpx.AsyncClient(timeout=20) as client:
            res = await client.get(url, headers={"Authorization": f"Bearer {self.api_key}"})
            _raise_for_status(res, scene="查询视频生成任务")
            payload = res.json()
        data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
        status = _normalize_status(_pick(data, "status", "task_status") or "generating")
        progress = float(_pick(data, "progress") or (1.0 if status == "ready" else 0.5))
        return ProviderJobStatus(
            provider_job_id=provider_job_id,
            status=status,
            progress=progress,
            output_video_url=_extract_video_url(data),
            duration=float(_pick(data, "duration") or 0),
            cover_url=str(_pick(data, "cover_url", "cover") or ""),
        )

    async def download(self, output_video_url: str, target_path: Path) -> Path:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        async with httpx.AsyncClient(timeout=180, follow_redirects=True) as client:
            async with client.stream("GET", output_video_url) as res:
                res.raise_for_status()
                with target_path.open("wb") as file:
                    async for chunk in res.aiter_bytes():
                        if chunk:
                            file.write(chunk)
        return target_path


def _seed_for_request(request: VideoGenerationRequest) -> int:
    """Keep one attempt reproducible while diversifying retry candidates."""
    digest = hashlib.sha1(request.job_id.encode("utf-8")).hexdigest()
    offset = int(digest[:8], 16) % 1_000_000
    return int(settings.aigc_video_seed) + offset


def _pick(payload: dict | None, *keys: str) -> Any:
    if not isinstance(payload, dict):
        return None
    for key in keys:
        value = payload.get(key)
        if value is not None:
            return value
    return None


def _build_content(request: VideoGenerationRequest) -> list[dict[str, Any]]:
    content: list[dict[str, Any]] = [{"type": "text", "text": request.prompt}]
    first_frame = resolve_provider_image(request.first_frame_url, request.first_frame_path)
    if first_frame:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": first_frame},
                "role": "first_frame",
            }
        )
    elif settings.aigc_video_require_first_frame:
        raise RuntimeError("当前任务缺少可读取的正片首帧，已阻止退化为文生视频")
    return content


def _input_mode(content: list[dict[str, Any]]) -> str:
    roles = {str(item.get("role") or "") for item in content}
    if {"first_frame", "last_frame"}.issubset(roles):
        return "first_last_frame_to_video"
    if "first_frame" in roles:
        return "first_frame_to_video"
    return "text_to_video"


def _extract_video_url(payload: dict | None) -> str:
    if not isinstance(payload, dict):
        return ""
    for key in ("output_video_url", "video_url", "file_url", "download_url", "output_url", "url"):
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    data = payload.get("data")
    if isinstance(data, dict):
        nested = _extract_video_url(data)
        if nested:
            return nested
    content = payload.get("content")
    if isinstance(content, dict):
        nested = _extract_video_url(content)
        if nested:
            return nested
    if isinstance(content, list):
        for item in content:
            nested = _extract_video_url(item)
            if nested:
                return nested
    outputs = payload.get("outputs") or payload.get("result")
    if isinstance(outputs, list):
        for item in outputs:
            nested = _extract_video_url(item)
            if nested:
                return nested
    if isinstance(outputs, dict):
        return _extract_video_url(outputs)
    return ""


def _normalize_status(status: Any) -> str:
    raw = str(status or "").lower()
    if raw in {"ready", "succeeded", "success", "completed", "done"}:
        return "ready"
    if raw in {"failed", "error", "cancelled", "canceled"}:
        return "failed"
    if raw in {"queued", "pending", "submitted"}:
        return "submitted"
    return "generating" if raw else ""


def _raise_for_status(res: httpx.Response, *, scene: str) -> None:
    try:
        res.raise_for_status()
    except httpx.HTTPStatusError as exc:
        body = exc.response.text[:800]
        raise RuntimeError(f"{scene}失败 HTTP {exc.response.status_code}: {body}") from exc


def _safe_payload(payload: dict) -> str:
    text = str(payload)
    return text[:500]
