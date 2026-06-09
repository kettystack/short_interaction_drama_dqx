"""根据 data/branches_config.json 剪出分支片段并生成 data/branches.json（供 /api/branches/seed 导入）。

用法：
    python ai_pipeline/cut_branches.py
"""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent           # short-drama-interaction/
DATA_DIR = ROOT / "data"
# 默认源目录（北派寻宝笔记）；clip 内可通过 `source_dir` 覆盖（如 tianxiadyi）
DEFAULT_VIDEO_ROOT = Path("/Users/daiqixu/Desktop/duanjujifa/juben/beipaixunbao")
DEFAULT_OUT_DIR = DEFAULT_VIDEO_ROOT / "branches"
CFG = DATA_DIR / "branches_config.json"
OUT_JSON = DATA_DIR / "branches.json"


def cut(src: Path, ss: float, to: float, dst: Path) -> None:
    """重编码切片（保证关键帧对齐 + 网页可流式播放）。"""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        print(f"[skip] {dst.name} already exists")
        return
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(ss),
        "-to", str(to),
        "-i", str(src),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        "-loglevel", "error",
        str(dst),
    ]
    print(f"[cut] {src.name} [{ss}-{to}] -> {dst.name}")
    subprocess.run(cmd, check=True)


def main() -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg not found in PATH")
    if not CFG.exists():
        raise SystemExit(f"config not found: {CFG}")

    cfg = json.loads(CFG.read_text(encoding="utf-8"))

    # 1) 切片
    for clip in cfg.get("clips", []):
        source_root = Path(clip.get("source_dir") or DEFAULT_VIDEO_ROOT)
        out_root = Path(clip.get("out_dir") or (source_root / "branches"))
        src = source_root / clip["source"]
        if not src.exists():
            raise SystemExit(f"source missing: {src}")
        dst = out_root / clip["out"]
        cut(src, float(clip["ss"]), float(clip["to"]), dst)

    # 2) 输出 seed json（剥离 clips，仅保留 forks）
    seed = {"forks": cfg["forks"]}
    OUT_JSON.write_text(
        json.dumps(seed, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[done] wrote {OUT_JSON}")
    print(f"\nnext: curl -X POST http://localhost:8000/api/branches/seed")


if __name__ == "__main__":
    main()
