"""关键帧抽取。

策略：
1. PySceneDetect 切场景，每个场景取中间帧 → 主候选
2. 固定 4s 间隔补一组 fallback 帧 → 兜底覆盖

输出：list[dict]  ts(秒)、path(jpg 路径)
"""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import List, TypedDict

from scenedetect import ContentDetector, SceneManager, open_video


class Frame(TypedDict):
    ts: float
    path: str


def detect_scenes(video_path: Path, threshold: float = 27.0) -> list[tuple[float, float]]:
    video = open_video(str(video_path))
    sm = SceneManager()
    sm.add_detector(ContentDetector(threshold=threshold))
    sm.detect_scenes(video=video, show_progress=False)
    scenes = sm.get_scene_list()
    return [(s.get_seconds(), e.get_seconds()) for s, e in scenes]


def _ffmpeg_grab(video_path: Path, ts: float, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-y", "-ss", f"{ts:.2f}", "-i", str(video_path),
            "-frames:v", "1", "-q:v", "3", "-vf", "scale=512:-1",
            str(out_path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def extract_frames(
    video_path: Path,
    out_dir: Path,
    fallback_interval: float = 4.0,
    max_duration: float | None = None,
) -> List[Frame]:
    out_dir.mkdir(parents=True, exist_ok=True)
    frames: list[Frame] = []
    seen_ts: set[int] = set()  # 去重（秒级）

    # 1) 场景中心帧
    scenes = detect_scenes(video_path)
    for start, end in scenes:
        ts = (start + end) / 2
        if max_duration and ts > max_duration:
            break
        key = int(ts)
        if key in seen_ts:
            continue
        seen_ts.add(key)
        path = out_dir / f"scene_{key:05d}.jpg"
        _ffmpeg_grab(video_path, ts, path)
        frames.append({"ts": ts, "path": str(path)})

    # 2) 均匀兜底帧（解决无场景切换的长镜头）
    duration = _get_duration(video_path)
    if max_duration:
        duration = min(duration, max_duration)
    t = 0.0
    while t < duration:
        key = int(t)
        if key not in seen_ts:
            seen_ts.add(key)
            path = out_dir / f"even_{key:05d}.jpg"
            _ffmpeg_grab(video_path, t, path)
            frames.append({"ts": t, "path": str(path)})
        t += fallback_interval

    frames.sort(key=lambda x: x["ts"])
    return frames


def _get_duration(video_path: Path) -> float:
    res = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(video_path)],
        capture_output=True, text=True, check=True,
    )
    return float(res.stdout.strip())


if __name__ == "__main__":
    import sys
    vp = Path(sys.argv[1])
    out = Path("./_frames") / vp.stem
    frames = extract_frames(vp, out)
    print(f"extracted {len(frames)} frames → {out}")
