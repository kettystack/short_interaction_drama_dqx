"""音频侧高光候选：用 RMS 能量峰值粗筛"情绪激烈"时间窗。

设计：
- ffmpeg 抽 mono / 16k / s16le PCM → numpy（避免引入 librosa 巨包）
- 计算固定 hop 的 RMS，做 Z-score
- 选 z > 阈值且彼此间距 ≥ min_gap 的局部峰值
- 输出 [{ts, score}], 供 highlight_detector 优先送入 Doubao 评估

成本：仅 numpy + ffmpeg；典型 30 分钟视频处理 < 3 秒。
"""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import TypedDict

import numpy as np


SAMPLE_RATE = 16_000


class AudioPeak(TypedDict):
    ts: float
    score: float


def _decode_pcm(video: Path) -> np.ndarray:
    """ffmpeg → s16le mono 16k → np.float32 in [-1,1]"""
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", str(video),
            "-ac", "1", "-ar", str(SAMPLE_RATE),
            "-f", "s16le", "-",
        ],
        capture_output=True, check=True,
    )
    raw = np.frombuffer(proc.stdout, dtype=np.int16)
    return raw.astype(np.float32) / 32768.0


def detect_audio_peaks(
    video: Path,
    hop_sec: float = 0.5,
    win_sec: float = 1.0,
    z_threshold: float = 1.8,
    min_gap_sec: float = 4.0,
    top_k: int = 60,
) -> list[AudioPeak]:
    """返回按时间排序的候选峰值列表。"""
    audio = _decode_pcm(video)
    hop = int(hop_sec * SAMPLE_RATE)
    win = int(win_sec * SAMPLE_RATE)
    if audio.size < win:
        return []

    # 滑窗 RMS
    n = (audio.size - win) // hop + 1
    rms = np.empty(n, dtype=np.float32)
    for i in range(n):
        seg = audio[i * hop : i * hop + win]
        rms[i] = np.sqrt(float(np.mean(seg * seg)) + 1e-12)

    # Z-score
    mu, sigma = float(rms.mean()), float(rms.std()) or 1.0
    z = (rms - mu) / sigma

    # 局部峰值（前后窗内最大）
    radius = max(1, int(min_gap_sec / hop_sec / 2))
    peaks: list[AudioPeak] = []
    for i in range(n):
        if z[i] < z_threshold:
            continue
        lo, hi = max(0, i - radius), min(n, i + radius + 1)
        if z[i] >= z[lo:hi].max():
            peaks.append({"ts": float(i * hop_sec), "score": float(z[i])})

    # 强度排序后截断，再按时间排回
    peaks.sort(key=lambda p: -p["score"])
    peaks = peaks[:top_k]
    peaks.sort(key=lambda p: p["ts"])
    return peaks


if __name__ == "__main__":
    import json
    import sys
    out = detect_audio_peaks(Path(sys.argv[1]))
    print(json.dumps(out, ensure_ascii=False, indent=2))
