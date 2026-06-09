from __future__ import annotations

import asyncio
import json
import re
import shutil
from pathlib import Path

from ...config import settings


async def normalize_and_inspect_video(
    *,
    source_path: Path,
    target_path: Path,
    review_dir: Path,
) -> tuple[Path, dict, list[Path]]:
    target_path.parent.mkdir(parents=True, exist_ok=True)
    review_dir.mkdir(parents=True, exist_ok=True)
    if settings.aigc_video_transcode_enabled:
        await _run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(source_path),
                "-map",
                "0:v:0",
                "-map",
                "0:a?",
                "-vf",
                (
                    f"scale={settings.aigc_video_target_width}:{settings.aigc_video_target_height}:"
                    "force_original_aspect_ratio=decrease,"
                    f"pad={settings.aigc_video_target_width}:{settings.aigc_video_target_height}:"
                    "(ow-iw)/2:(oh-ih)/2:black"
                ),
                "-c:v",
                "libx264",
                "-preset",
                "medium",
                "-crf",
                "20",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                "-c:a",
                "aac",
                "-b:a",
                "128k",
                str(target_path),
            ]
        )
    elif source_path.resolve() != target_path.resolve():
        shutil.copyfile(source_path, target_path)

    metrics = await probe_video(target_path)
    frames = await extract_review_frames(
        target_path,
        review_dir=review_dir,
        duration=float(metrics.get("duration") or 0.0),
    )
    metrics["technical_score"], metrics["technical_pass"], reasons = _technical_score(metrics)
    metrics["technical_reasons"] = reasons
    return target_path, metrics, frames


async def probe_video(path: Path) -> dict:
    output = await _run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=index,codec_type,codec_name,width,height,pix_fmt,r_frame_rate:format=duration,size",
            "-of",
            "json",
            str(path),
        ]
    )
    payload = json.loads(output or "{}")
    streams = payload.get("streams") or []
    video = next((item for item in streams if item.get("codec_type") == "video"), {})
    width = int(video.get("width") or 0)
    height = int(video.get("height") or 0)
    duration = float((payload.get("format") or {}).get("duration") or 0.0)
    return {
        "path": str(path),
        "width": width,
        "height": height,
        "ratio": (width / height) if height else 0.0,
        "duration": duration,
        "codec": str(video.get("codec_name") or ""),
        "pix_fmt": str(video.get("pix_fmt") or ""),
        "fps": str(video.get("r_frame_rate") or ""),
        "size_bytes": int((payload.get("format") or {}).get("size") or 0),
    }


async def extract_review_frames(
    video_path: Path,
    *,
    review_dir: Path,
    duration: float,
) -> list[Path]:
    if duration <= 0:
        timestamps = [0.0]
    else:
        timestamps = [0.05, max(duration * 0.5, 0.05), max(duration - 0.12, 0.05)]
    frames: list[Path] = []
    for index, timestamp in enumerate(timestamps):
        target = review_dir / f"generated_{index}.jpg"
        await _run(
            [
                "ffmpeg",
                "-y",
                "-ss",
                f"{timestamp:.3f}",
                "-i",
                str(video_path),
                "-frames:v",
                "1",
                "-q:v",
                "2",
                str(target),
            ]
        )
        if target.is_file():
            frames.append(target)
    return frames


async def compare_frame_ssim(reference: Path, candidate: Path) -> float:
    process = await asyncio.create_subprocess_exec(
        "ffmpeg",
        "-i",
        str(reference),
        "-i",
        str(candidate),
        "-lavfi",
        "[0:v]scale=360:640[a];[1:v]scale=360:640[b];[a][b]ssim",
        "-f",
        "null",
        "-",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await process.communicate()
    detail = stderr.decode("utf-8", errors="replace")
    if process.returncode != 0:
        raise RuntimeError(f"首帧相似度计算失败: {detail[-800:]}")
    match = re.search(r"All:([0-9.]+)", detail)
    if not match:
        raise RuntimeError("首帧相似度计算结果缺少 SSIM")
    return max(0.0, min(float(match.group(1)), 1.0))


def _technical_score(metrics: dict) -> tuple[float, bool, list[str]]:
    reasons: list[str] = []
    score = 1.0
    duration = float(metrics.get("duration") or 0.0)
    ratio = float(metrics.get("ratio") or 0.0)
    width = int(metrics.get("width") or 0)
    height = int(metrics.get("height") or 0)

    if not 2.0 <= duration <= 15.5:
        score -= 0.35
        reasons.append(f"时长 {duration:.2f}s 不在 2-15s")
    else:
        reasons.append(f"时长 {duration:.2f}s 合格")
    if abs(ratio - (9 / 16)) > 0.06:
        score -= 0.35
        reasons.append(f"宽高比 {ratio:.3f} 不是竖屏 9:16")
    else:
        reasons.append("竖屏比例合格")
    if width < 540 or height < 960:
        score -= 0.2
        reasons.append(f"分辨率 {width}x{height} 偏低")
    else:
        reasons.append(f"分辨率 {width}x{height} 合格")
    if not metrics.get("codec"):
        score -= 0.2
        reasons.append("未识别到视频编码")
    return max(score, 0.0), score >= 0.72, reasons


async def _run(args: list[str]) -> str:
    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        detail = stderr.decode("utf-8", errors="replace")[-1200:]
        raise RuntimeError(f"媒体处理失败 ({args[0]}): {detail}")
    return stdout.decode("utf-8", errors="replace")
