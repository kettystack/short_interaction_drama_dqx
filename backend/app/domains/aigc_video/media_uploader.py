from __future__ import annotations

import base64
import mimetypes
from pathlib import Path
from urllib.parse import urlparse

from ...config import settings

_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "0.0.0.0"}


def externalize_media_url(url: str) -> str:
    """Return a URL that a cloud video provider can fetch.

    Local demo frame URLs point at 127.0.0.1 and cannot be reached by Ark.
    When AIGC_MEDIA_PUBLIC_BASE_URL is configured, map local /frames URLs to
    that public base. Otherwise drop local media and let Seedance run T2V.
    """
    clean = (url or "").strip()
    if not clean:
        return ""
    if clean.startswith("data:image/"):
        return clean

    public_base = settings.aigc_media_public_base_url.strip().rstrip("/")
    app_base = settings.public_base_url.strip().rstrip("/")
    if public_base:
        if clean.startswith("/"):
            return f"{public_base}{clean}"
        if app_base and clean.startswith(app_base):
            return f"{public_base}{clean[len(app_base):]}"

    parsed = urlparse(clean)
    if parsed.scheme not in {"http", "https"}:
        return ""
    if (parsed.hostname or "").lower() in _LOCAL_HOSTS:
        return ""
    return clean


def resolve_provider_image(url: str, local_path: str) -> str:
    """Resolve a provider-readable image, preferring public URL then Base64."""
    external = externalize_media_url(url)
    if external:
        return external
    path = Path(local_path).expanduser() if local_path else None
    if path is None or not path.is_file():
        return ""
    if path.stat().st_size >= 30 * 1024 * 1024:
        raise ValueError(f"首帧图片超过 30MB: {path}")
    mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    if not mime.startswith("image/"):
        raise ValueError(f"首帧不是支持的图片格式: {path}")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime.lower()};base64,{encoded}"
