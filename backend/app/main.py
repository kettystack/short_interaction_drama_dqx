from contextlib import asynccontextmanager
import mimetypes
from pathlib import Path
from typing import Iterator

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from .api import admin, aigc_video, analytics, assets, auth, branch_generation, branch_video, branches, danmaku, episodes, evaluation, feed, highlights, interactions, interactive_drama, media, narrative, recommendations, story_chat, users, vip
from .config import settings
from .database import init_db


mimetypes.add_type("application/vnd.apple.mpegurl", ".m3u8")
mimetypes.add_type("video/iso.segment", ".m4s")
mimetypes.add_type("video/mp2t", ".ts")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="Short Drama Interaction", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(episodes.router)
app.include_router(auth.router)
app.include_router(highlights.router)
app.include_router(interactions.router)
app.include_router(interactive_drama.router)
app.include_router(branches.router)
app.include_router(branch_generation.router)
app.include_router(branch_video.router)
app.include_router(narrative.router)
app.include_router(danmaku.router)
app.include_router(users.router)
app.include_router(analytics.router)
app.include_router(recommendations.router)
app.include_router(media.router)
app.include_router(feed.router)
app.include_router(story_chat.router)
app.include_router(vip.router)
app.include_router(aigc_video.router)
app.include_router(evaluation.router)
app.include_router(admin.router)
app.include_router(assets.router)


video_dir = Path(settings.video_root).resolve()
tianxiadyi_video_dir = Path(settings.tianxiadyi_video_root).resolve()
shibasuitainainai_video_dir = Path(settings.shibasuitainainai_video_root).resolve()
hls_dir = (Path(settings.data_root) / "hls").resolve()
frames_dir = (Path(settings.data_root) / "frames").resolve()
generated_dir = Path(settings.generated_media_root).resolve()


def _iter_file_range(path: Path, start: int, end: int, chunk_size: int = 1024 * 1024) -> Iterator[bytes]:
    with path.open("rb") as file:
        file.seek(start)
        remaining = end - start + 1
        while remaining > 0:
            chunk = file.read(min(chunk_size, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk


def _resolve_video_path(file_path: str) -> Path:
    candidates: list[tuple[Path, str]] = [(video_dir, file_path)]
    if file_path.startswith("tianxiadyi/"):
        candidates.insert(0, (tianxiadyi_video_dir, file_path.removeprefix("tianxiadyi/")))
    if file_path.startswith("shibasuitainainai/"):
        candidates.insert(
            0,
            (
                shibasuitainainai_video_dir,
                file_path.removeprefix("shibasuitainainai/"),
            ),
        )

    for root, relative_path in candidates:
        if not root.exists():
            continue
        path = (root / relative_path).resolve()
        if root not in path.parents and path != root:
            continue
        if path.is_file():
            return path
    raise HTTPException(404, "video not found")


def _resolve_hls_path(file_path: str) -> Path:
    if not hls_dir.exists():
        raise HTTPException(404, "hls root not found")
    path = (hls_dir / file_path).resolve()
    if hls_dir not in path.parents and path != hls_dir:
        raise HTTPException(403, "invalid hls path")
    if not path.is_file():
        raise HTTPException(404, "hls asset not found")
    return path


def _resolve_generated_path(file_path: str) -> Path:
    if not generated_dir.exists():
        raise HTTPException(404, "generated root not found")
    path = (generated_dir / file_path).resolve()
    if generated_dir not in path.parents and path != generated_dir:
        raise HTTPException(403, "invalid generated path")
    if not path.is_file():
        raise HTTPException(404, "generated asset not found")
    return path


@app.api_route("/videos/{file_path:path}", methods=["GET", "HEAD"], operation_id="serve_video")
async def serve_video(file_path: str, request: Request):
    path = _resolve_video_path(file_path)
    file_size = path.stat().st_size
    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    range_header = request.headers.get("range")

    if not range_header:
        headers = {
            "Accept-Ranges": "bytes",
            "Content-Length": str(file_size),
            "Content-Type": media_type,
        }
        if request.method == "HEAD":
            return Response(headers=headers, media_type=media_type)
        return StreamingResponse(
            _iter_file_range(path, 0, file_size - 1),
            headers=headers,
            media_type=media_type,
        )

    try:
        unit, value = range_header.split("=", 1)
        if unit != "bytes":
            raise ValueError
        start_text, end_text = value.split("-", 1)
        if start_text:
            start = int(start_text)
            end = int(end_text) if end_text else file_size - 1
        else:
            suffix_length = int(end_text)
            start = max(file_size - suffix_length, 0)
            end = file_size - 1
        end = min(end, file_size - 1)
        if start < 0 or start > end:
            raise ValueError
    except ValueError:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )

    content_length = end - start + 1
    headers = {
        "Accept-Ranges": "bytes",
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Content-Length": str(content_length),
        "Content-Type": media_type,
    }
    if request.method == "HEAD":
        return Response(status_code=206, headers=headers, media_type=media_type)
    return StreamingResponse(
        _iter_file_range(path, start, end),
        status_code=206,
        headers=headers,
        media_type=media_type,
    )


@app.api_route("/hls/{file_path:path}", methods=["GET", "HEAD"], operation_id="serve_hls")
async def serve_hls(file_path: str, request: Request):
    path = _resolve_hls_path(file_path)
    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    file_size = path.stat().st_size
    cache_control = "no-cache" if path.suffix == ".m3u8" else "public, max-age=3600"
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": cache_control,
        "Content-Length": str(file_size),
        "Content-Type": media_type,
    }
    if request.method == "HEAD":
        return Response(headers=headers, media_type=media_type)
    return StreamingResponse(
        _iter_file_range(path, 0, file_size - 1),
        headers=headers,
        media_type=media_type,
    )


@app.api_route("/generated/{file_path:path}", methods=["GET", "HEAD"], operation_id="serve_generated")
async def serve_generated(file_path: str, request: Request):
    path = _resolve_generated_path(file_path)
    file_size = path.stat().st_size
    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    range_header = request.headers.get("range")
    if not range_header:
        headers = {
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=3600",
            "Content-Length": str(file_size),
            "Content-Type": media_type,
        }
        if request.method == "HEAD":
            return Response(headers=headers, media_type=media_type)
        return StreamingResponse(
            _iter_file_range(path, 0, file_size - 1),
            headers=headers,
            media_type=media_type,
        )
    try:
        unit, value = range_header.split("=", 1)
        if unit != "bytes":
            raise ValueError
        start_text, end_text = value.split("-", 1)
        start = int(start_text) if start_text else 0
        end = int(end_text) if end_text else file_size - 1
        end = min(end, file_size - 1)
        if start < 0 or start > end:
            raise ValueError
    except ValueError:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=3600",
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Content-Length": str(end - start + 1),
        "Content-Type": media_type,
    }
    if request.method == "HEAD":
        return Response(status_code=206, headers=headers, media_type=media_type)
    return StreamingResponse(
        _iter_file_range(path, start, end),
        status_code=206,
        headers=headers,
        media_type=media_type,
    )



@app.api_route("/frames/{file_path:path}", methods=["GET", "HEAD"], operation_id="serve_frame")
async def serve_frame(file_path: str, request: Request):
    if not frames_dir.exists():
        raise HTTPException(404, "frames root not found")
    path = (frames_dir / file_path).resolve()
    if frames_dir not in path.parents and path != frames_dir:
        raise HTTPException(403, "invalid frame path")
    if not path.is_file():
        raise HTTPException(404, "frame not found")
    media_type = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    file_size = path.stat().st_size
    headers = {
        "Cache-Control": "public, max-age=86400",
        "Content-Length": str(file_size),
        "Content-Type": media_type,
    }
    if request.method == "HEAD":
        return Response(headers=headers, media_type=media_type)
    return StreamingResponse(_iter_file_range(path, 0, file_size - 1), headers=headers, media_type=media_type)


@app.get("/")
async def root():
    return {"app": "short-drama-interaction", "status": "ok"}
