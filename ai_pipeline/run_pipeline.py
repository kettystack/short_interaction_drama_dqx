"""一键 AI Pipeline：mp4 → highlights.json。

用法：
    单集：
        python run_pipeline.py --video ../../beipaixunbao/第63集.mp4 \
            --episode-id ep_063 --out ../data/highlights/ep_063.json

    批量：
        python run_pipeline.py --batch ../../beipaixunbao --out-dir ../data/highlights
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:  # 允许只通过 shell export 注入环境变量运行
    def load_dotenv(*_args, **_kwargs):
        return False

from extract_frames import extract_frames
from highlight_detector import build_windows, detect_batch, normalize_highlights

load_dotenv()


def _filter_windows_by_candidates(
    wins: list[dict],
    audio_peaks: list[dict] | None,
    scene_cuts: list[dict] | None,
    window_size: float,
) -> list[dict]:
    """保留命中音频峰或镜头切点的窗口；两者均为空则不过滤。"""
    if not audio_peaks and not scene_cuts:
        return wins
    peak_ts = [p["ts"] for p in (audio_peaks or [])]
    cut_ts = [c["ts"] for c in (scene_cuts or [])]
    half = window_size / 2
    kept: list[dict] = []
    for w in wins:
        lo, hi = w["ts"] - half, w["ts"] + half
        if any(lo <= t <= hi for t in peak_ts) or any(lo <= t <= hi for t in cut_ts):
            kept.append(w)
    return kept or wins  # 全没命中就退回全量，避免 0 召回


def _duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return float(out)


def run_one(video: Path, episode_id: str, out: Path, work_dir: Path, skip_asr: bool = False, candidates: str = "") -> None:
    print(f"\n=== {episode_id} : {video.name} ===")
    frames_dir = work_dir / "frames" / episode_id
    print("[1/3] 抽帧 ...")
    frames = extract_frames(video, frames_dir, fallback_interval=4.0)
    print(f"     -> {len(frames)} 帧")

    if skip_asr:
        segs: list[dict] = []
        print("[2/3] 跳过 Whisper")
    else:
        from whisper_asr import transcribe  # 仅在需要时导入，避免 torch 依赖
        print("[2/3] Whisper 字幕 ...")
        segs = transcribe(video)
        (work_dir / "subtitles").mkdir(parents=True, exist_ok=True)
        (work_dir / "subtitles" / f"{episode_id}.json").write_text(
            json.dumps(segs, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"     -> {len(segs)} segments")

    # 候选源（可选）：audio / scene
    audio_peaks: list[dict] = []
    scene_cuts: list[dict] = []
    sources = {s.strip() for s in candidates.split(",") if s.strip()}
    if "audio" in sources:
        from audio_highlight import detect_audio_peaks
        print("[2.5] 音频能量峰值 ...")
        audio_peaks = [dict(p) for p in detect_audio_peaks(video)]
        print(f"     -> {len(audio_peaks)} 个候选峰")
    if "scene" in sources:
        from scene_detect import detect_scene_cuts
        print("[2.6] 镜头切点 ...")
        scene_cuts = [dict(c) for c in detect_scene_cuts(video)]
        print(f"     -> {len(scene_cuts)} 个镜头")

    print("[3/3] Doubao 高光识别 ...")
    wins = build_windows([dict(f) for f in frames], [dict(s) for s in segs], window_size=8.0)
    if sources:
        kept = _filter_windows_by_candidates(wins, audio_peaks, scene_cuts, 8.0)
        print(f"     窗口筛选 {len(wins)} -> {len(kept)}")
        wins = kept
    print(f"     窗口数: {len(wins)}")
    hits = detect_batch(wins, batch_size=4)
    duration = _duration(video)
    hits = normalize_highlights(hits, duration=duration)
    print(f"     -> {len(hits)} 个高光")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(
            {
                "episode_id": episode_id,
                "duration": duration,
                "highlights": hits,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"     写入 {out}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--video", type=Path)
    p.add_argument("--episode-id")
    p.add_argument("--out", type=Path)
    p.add_argument("--batch", type=Path, help="批量模式：扫描目录下所有 mp4")
    p.add_argument("--out-dir", type=Path, default=Path("../data/highlights"))
    p.add_argument("--work-dir", type=Path, default=Path("../data"))
    p.add_argument("--prefix", default="ep_", help="episode_id 前缀，例如 ep_/txy_")
    p.add_argument("--only", default="", help="逗号分隔的集号过滤，例如 1,2,3,4,5")
    p.add_argument("--skip-asr", action="store_true", help="跳过 Whisper（无字幕，仅靠画面识别）")
    p.add_argument("--candidates", default="", help="高光候选源，逗号分隔：audio,scene")
    args = p.parse_args()

    if args.batch:
        only = {int(x) for x in args.only.split(",") if x.strip().isdigit()} if args.only else None
        for v in sorted(args.batch.glob("第*.mp4")):
            m = re.search(r"第(\d+)集", v.name)
            if not m:
                continue
            n = int(m.group(1))
            if only and n not in only:
                continue
            ep = f"{args.prefix}{n:03d}"
            out = args.out_dir / f"{ep}.json"
            if out.exists():
                print(f"skip {ep} (exists)")
                continue
            run_one(v, ep, out, args.work_dir, skip_asr=args.skip_asr, candidates=args.candidates)
        return

    if not (args.video and args.episode_id and args.out):
        p.error("单集模式需要 --video --episode-id --out")
    run_one(args.video, args.episode_id, args.out, args.work_dir, skip_asr=args.skip_asr, candidates=args.candidates)


if __name__ == "__main__":
    main()
