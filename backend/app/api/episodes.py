import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import get_db
from ..models import Episode
from ..schemas import EpisodeOut, HlsVariantOut

router = APIRouter(prefix="/api/episodes", tags=["episodes"])

hls_root = (Path(settings.data_root) / "hls").resolve()
frames_root = (Path(settings.data_root) / "frames").resolve()

_bandwidth_re = re.compile(r"BANDWIDTH=(\d+)")
_resolution_re = re.compile(r"RESOLUTION=(\d+)x(\d+)")
_episode_no_re = re.compile(r"第\d+集")
_BPXB_SOURCE_START = 63
_BPXB_TITLE = "北派寻宝笔记"


def _pick_cover(episode_id: str) -> str:
    folder = frames_root / episode_id
    if not folder.is_dir():
        return ""
    images = sorted(folder.glob("*.jpg"))
    if not images:
        return ""
    pick = images[len(images) // 3] if len(images) > 3 else images[0]
    return f"/frames/{episode_id}/{pick.name}"


def _hls_variants(episode_id: str) -> list[HlsVariantOut]:
    master = hls_root / episode_id / "master.m3u8"
    if not master.is_file():
        return []
    lines = master.read_text(encoding="utf-8").splitlines()
    variants: list[HlsVariantOut] = []
    for index, line in enumerate(lines):
        if not line.startswith("#EXT-X-STREAM-INF") or index + 1 >= len(lines):
            continue
        playlist = lines[index + 1].strip()
        if not playlist or playlist.startswith("#"):
            continue
        clean_playlist = playlist.split("?", 1)[0]
        parts = Path(clean_playlist).parts
        label = parts[0] if len(parts) > 1 else Path(clean_playlist).stem
        bandwidth_match = _bandwidth_re.search(line)
        resolution_match = _resolution_re.search(line)
        width = height = None
        if resolution_match:
            width = int(resolution_match.group(1))
            height = int(resolution_match.group(2))
        variants.append(
            HlsVariantOut(
                label=label,
                url=playlist if playlist.startswith("/hls/") else f"/hls/{episode_id}/{playlist}",
                width=width,
                height=height,
                bandwidth=int(bandwidth_match.group(1)) if bandwidth_match else None,
            )
        )
    return variants


def episode_to_out(episode: Episode) -> EpisodeOut:
    hls_manifest = hls_root / episode.id / "master.m3u8"
    hls_ready = hls_manifest.is_file()
    cover = episode.cover_url or _pick_cover(episode.id)
    episode_no = episode.episode_no
    title = episode.title
    if episode.drama_id == "beipaixunbao" and episode.episode_no >= _BPXB_SOURCE_START:
        episode_no = episode.episode_no - _BPXB_SOURCE_START + 1
        title = _episode_no_re.sub(f"第{episode_no}集", title)
        if title == episode.title:
            title = f"{_BPXB_TITLE} 第{episode_no}集"
    return EpisodeOut.model_validate(episode).model_copy(
        update={
            "title": title,
            "episode_no": episode_no,
            "hls_url": f"/hls/{episode.id}/master.m3u8" if hls_ready else None,
            "hls_ready": hls_ready,
            "hls_variants": _hls_variants(episode.id),
            "cover_url": cover,
        }
    )


@router.get("", response_model=list[EpisodeOut])
async def list_episodes(drama_id: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(Episode)
    if drama_id:
        query = query.where(Episode.drama_id == drama_id)
    res = await db.execute(query.order_by(Episode.drama_id, Episode.episode_no))
    return [episode_to_out(episode) for episode in res.scalars().all()]


@router.get("/{episode_id}", response_model=EpisodeOut)
async def get_episode(episode_id: str, db: AsyncSession = Depends(get_db)):
    ep = await db.get(Episode, episode_id)
    if not ep:
        raise HTTPException(404, "episode not found")
    return episode_to_out(ep)
