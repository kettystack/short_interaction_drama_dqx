"""Whisper 字幕提取，输出带时间戳的 segments。

Mac Apple Silicon 默认走 MPS；如不支持自动回退 CPU。
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import TypedDict

import whisper


class Segment(TypedDict):
    start: float
    end: float
    text: str


_MODEL = None


def _load_model():
    global _MODEL
    if _MODEL is not None:
        return _MODEL
    name = os.getenv("WHISPER_MODEL", "small")
    device = os.getenv("WHISPER_DEVICE", "cpu")
    # whisper 官方暂未直接支持 mps；Mac 上更稳的是 cpu
    # 若你装了 mlx-whisper / faster-whisper 可在此替换
    if device == "mps":
        device = "cpu"
    _MODEL = whisper.load_model(name, device=device)
    return _MODEL


def transcribe(video_path: Path, language: str = "zh") -> list[Segment]:
    model = _load_model()
    result = model.transcribe(
        str(video_path),
        language=language,
        task="transcribe",
        verbose=False,
        fp16=False,
    )
    segs: list[Segment] = []
    for s in result.get("segments", []):
        segs.append({"start": float(s["start"]), "end": float(s["end"]), "text": s["text"].strip()})
    return segs


def segments_in_window(segments: list[Segment], ts: float, window: float = 4.0) -> str:
    """取 [ts-window, ts+window] 内字幕拼成一段。"""
    lo, hi = ts - window, ts + window
    parts = [s["text"] for s in segments if s["end"] >= lo and s["start"] <= hi]
    return " ".join(parts)


if __name__ == "__main__":
    import json
    import sys
    segs = transcribe(Path(sys.argv[1]))
    print(json.dumps(segs[:10], ensure_ascii=False, indent=2))
