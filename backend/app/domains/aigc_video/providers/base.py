from __future__ import annotations

from typing import Protocol
from pathlib import Path

from ..schemas import ProviderJob, ProviderJobStatus, VideoGenerationRequest


class VideoGenerationProvider(Protocol):
    async def submit(self, request: VideoGenerationRequest) -> ProviderJob:
        ...

    async def poll(self, provider_job_id: str) -> ProviderJobStatus:
        ...

    async def download(self, output_video_url: str, target_path: Path) -> Path:
        ...
