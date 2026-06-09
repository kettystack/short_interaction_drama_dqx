#!/usr/bin/env python3
"""剧情分支切片 —— 按 data/branches_config.json 用 ffmpeg 从真实剧集剪出分支片段。

设计：
- 每个 clip 指定 source / ss / to，可选 source_dir / out_dir；
- 默认 source_dir = beipaixunbao 视频根，out_dir = <source_dir>/branches；
- 重编码切片（libx264 + aac），保证关键帧对齐、分支片段可独立播放；
- 幂等：已存在且未加 --force 时跳过。

用法：
    python3 scripts/build_branches.py
    python3 scripts/build_branches.py --only txy_001_b1.mp4 --force
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "data" / "branches_config.json"
DEFAULT_SOURCE_DIR = (ROOT.parent / "juben" / "beipaixunbao")


def cut(src: Path, dst: Path, ss: float, to: float) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(ss), "-to", str(to),
        "-i", str(src),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        str(dst),
    ]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def main() -> None:
    ap = argparse.ArgumentParser(description="Cut branch clips from real episodes.")
    ap.add_argument("--only", nargs="*", help="只切指定 out 文件名")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    only = set(args.only or [])

    for clip in config.get("clips", []):
        out_name = clip["out"]
        if only and out_name not in only:
            continue
        source_dir = Path(clip.get("source_dir", DEFAULT_SOURCE_DIR))
        out_dir = Path(clip.get("out_dir", source_dir / "branches"))
        src = source_dir / clip["source"]
        dst = out_dir / out_name

        if not src.exists():
            print(f"{out_name}: SKIP (no source {src})")
            continue
        if dst.exists() and not args.force:
            print(f"{out_name}: skip (exists)")
            continue

        try:
            cut(src, dst, float(clip["ss"]), float(clip["to"]))
            size = dst.stat().st_size // 1024
            print(f"{out_name}: ok ({size} KB) <- {clip['source']} [{clip['ss']}-{clip['to']}]")
        except subprocess.CalledProcessError as exc:
            print(f"{out_name}: FFMPEG FAIL\n{exc.stderr[-400:]}")


if __name__ == "__main__":
    main()
