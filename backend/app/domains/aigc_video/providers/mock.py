from __future__ import annotations

import hashlib
from pathlib import Path

from ..schemas import ProviderJob, ProviderJobStatus, VideoGenerationRequest


class MockVideoGenerationProvider:
    async def submit(self, request: VideoGenerationRequest) -> ProviderJob:
        digest = hashlib.sha1(request.job_id.encode("utf-8")).hexdigest()[:10]
        return ProviderJob(provider_job_id=f"mock_{digest}", status="ready", progress=1.0)

    async def poll(self, provider_job_id: str) -> ProviderJobStatus:
        # The service resolves the final URL from episode context; provider is stateless.
        return ProviderJobStatus(
            provider_job_id=provider_job_id,
            status="ready",
            progress=1.0,
        )

    async def download(self, output_video_url: str, target_path: Path) -> Path:
        raise NotImplementedError("mock provider does not download remote assets")
