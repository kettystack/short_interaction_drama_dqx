import argparse
import asyncio
import shutil
import subprocess
import time
from pathlib import Path

from sqlalchemy import select

from app.config import settings
from app.database import SessionLocal, init_db
from app.models import EpisodeAsset


# (height, maxrate, label, codec, crf)
# 短剧为竖屏 1080x1920 源，提升清晰度档位
VARIANTS = [
    (480, 1_200_000, "480p", "avc1.4d401e", 23),
    (720, 2_800_000, "720p", "avc1.4d401f", 21),
    (1080, 5_000_000, "1080p", "avc1.640028", 19),
]


def episode_no(episode_id: str) -> int:
    return int(episode_id.rsplit("_", 1)[1])


def source_path(episode_id: str) -> Path:
    if episode_id.startswith("txy_"):
        return Path(settings.tianxiadyi_video_root).resolve() / f"第{episode_no(episode_id)}集.mp4"
    return Path(settings.video_root).resolve() / f"第{episode_no(episode_id)}集.mp4"


def output_root(episode_id: str) -> Path:
    return (Path(settings.data_root) / "hls" / episode_id).resolve()


def run_ffmpeg(source: Path, output: Path, height: int, maxrate: int, crf: int, profile: str) -> None:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    # 短剧多为竖屏，按高度等比缩放，宽度自动；强制偶数
    command = [
        "ffmpeg",
        "-y",
        "-i",
        str(source),
        "-map",
        "0:v:0",
        "-map",
        "0:a?",
        "-vf",
        f"scale=-2:{height}:flags=lanczos",
        "-c:v",
        "libx264",
        "-profile:v",
        profile,
        "-level:v",
        "4.1",
        "-preset",
        "medium",
        "-crf",
        str(crf),
        "-maxrate",
        str(maxrate),
        "-bufsize",
        str(maxrate * 2),
        "-pix_fmt",
        "yuv420p",
        "-g",
        "96",
        "-keyint_min",
        "96",
        "-sc_threshold",
        "0",
        "-c:a",
        "aac",
        "-profile:a",
        "aac_low",
        "-ac",
        "2",
        "-ar",
        "44100",
        "-b:a",
        "128k",
        "-movflags",
        "+faststart",
        "-hls_time",
        "4",
        "-hls_playlist_type",
        "vod",
        "-hls_segment_type",
        "fmp4",
        "-hls_segment_filename",
        str(output / "seg_%05d.m4s"),
        str(output / "index.m3u8"),
    ]
    subprocess.run(command, check=True)


def write_master(root: Path) -> None:
    cache_buster = int(time.time())
    lines = ["#EXTM3U", "#EXT-X-VERSION:7"]
    # 高画质放第一位，让默认首选 1080p
    for height, bandwidth, label, video_codec, _crf in sorted(VARIANTS, key=lambda v: -v[0]):
        width = round(height * 9 / 16)
        if width % 2:
            width += 1
        lines.append(
            f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},RESOLUTION={width}x{height},"
            f'CODECS="{video_codec},mp4a.40.2"'
        )
        lines.append(f"{label}/index.m3u8?v={cache_buster}")
    (root / "master.m3u8").write_text("\n".join(lines) + "\n", encoding="utf-8")


async def persist_assets(episode_id: str) -> None:
    await init_db()
    async with SessionLocal() as db:
        rows = [
            ("master", f"/hls/{episode_id}/master.m3u8", None, None, None),
            *[
                (
                    label,
                    f"/hls/{episode_id}/{label}/index.m3u8",
                    (height * 9 // 16) + ((height * 9 // 16) % 2),
                    height,
                    bandwidth,
                )
                for height, bandwidth, label, _video_codec, _crf in VARIANTS
            ],
        ]
        for label, url, width, height, bandwidth in rows:
            result = await db.execute(
                select(EpisodeAsset).where(
                    EpisodeAsset.episode_id == episode_id,
                    EpisodeAsset.kind == "hls",
                    EpisodeAsset.label == label,
                )
            )
            asset = result.scalar_one_or_none()
            if asset is None:
                asset = EpisodeAsset(episode_id=episode_id, kind="hls", label=label, url=url)
                db.add(asset)
            asset.url = url
            asset.width = width
            asset.height = height
            asset.bandwidth = bandwidth
            asset.is_ready = True
            asset.storage = "local"
        await db.commit()


def build_episode(episode_id: str) -> None:
    source = source_path(episode_id)
    if not source.is_file():
        raise FileNotFoundError(f"video not found: {source}")
    root = output_root(episode_id)
    for height, maxrate, label, _video_codec, crf in VARIANTS:
        profile = "high" if height >= 1080 else "main"
        run_ffmpeg(source, root / label, height, maxrate, crf, profile)
    write_master(root)
    asyncio.run(persist_assets(episode_id))
    print(f"HLS ready: {root / 'master.m3u8'}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build HLS ABR assets for one episode.")
    parser.add_argument("episode_id", help="episode id, e.g. ep_063")
    args = parser.parse_args()
    build_episode(args.episode_id)


if __name__ == "__main__":
    main()