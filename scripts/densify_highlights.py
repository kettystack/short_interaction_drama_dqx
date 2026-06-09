#!/usr/bin/env python3
"""高光增密 —— 在 AI 识别出的高光之间补充「氛围」高光节拍，让互动更密集、不平淡。

策略：
- 保留 AI 原始高光（source=ai）不动；
- 在相邻高光、以及片头/片尾的较大空档里，按 ~SPACING 秒插入氛围节拍；
- 氛围节拍 intensity 偏低（0.5~0.6），类型在邻近高光基础上做合理轮换，
  这样大特效仍以真实高光为主，氛围节拍负责「持续有反应」的临场感；
- 幂等：重跑时先剔除已有 source=ambient 的节拍再重算。

用法：
    python3 scripts/densify_highlights.py            # 增密 data/highlights/*.json
    python3 scripts/densify_highlights.py txy_014     # 只处理指定剧集
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "highlights"

SPACING = 9.0          # 氛围节拍目标间隔（秒）
MIN_GAP = 11.0          # 空档大于该值才填充
WINDOW = 6.0            # 单个氛围节拍时长
EDGE = 3.0             # 片头/片尾留白
KEEP_CLEAR = 3.0        # 与真实高光保持的最小间距

INTERACTION_MAP = {
    "冲突": "燃", "反转": "爽", "甜蜜": "甜", "搞笑": "笑",
    "名场面": "封神", "虐心": "哭", "悬念": "炸裂",
    "爽点": "爽", "打脸": "爽", "反杀": "爽", "解气": "爽",
    "震惊": "惊", "紧张": "屏息", "压迫": "屏息",
    "破防": "破防", "心疼": "心疼", "高甜": "甜", "磕糖": "磕",
    "离谱": "离谱", "上头": "上头", "治愈": "治愈",
}
# 氛围节拍轮换类型（去掉过重的「虐心」，保证整体观感不压抑）
CYCLE = ["搞笑", "爽点", "打脸", "紧张", "高甜", "磕糖", "上头", "治愈", "名场面"]
DESC = {
    "搞笑": "弹幕笑成一片", "悬念": "气氛悬起来了", "甜蜜": "甜度持续上升",
    "冲突": "火药味渐浓", "反转": "细节藏着反转", "名场面": "名场面前奏",
    "爽点": "爽点开始聚集", "打脸": "打脸预感来了", "反杀": "反杀气势升起",
    "解气": "观众开始解气", "震惊": "观众被震住了", "紧张": "紧张感拉满",
    "压迫": "压迫感逼近", "破防": "情绪开始破防", "心疼": "心疼情绪升起",
    "高甜": "甜度持续上升", "磕糖": "观众开始磕糖", "离谱": "弹幕直呼离谱",
    "上头": "越看越上头", "治愈": "气氛开始变暖",
}


def _beat(ts: float, kind: str, seq: int) -> dict:
    intensity = round(0.5 + (seq % 3) * 0.04, 2)
    return {
        "ts_start": round(ts, 2),
        "ts_end": round(ts + WINDOW, 2),
        "type": kind,
        "interaction": INTERACTION_MAP.get(kind, "爽"),
        "intensity": intensity,
        "description": DESC.get(kind, "气氛升温"),
        "source": "ambient",
    }


def _overlaps(ts: float, reals: list[dict]) -> bool:
    for h in reals:
        if h["ts_start"] - KEEP_CLEAR <= ts <= h["ts_end"] + KEEP_CLEAR:
            return True
    return False


def densify(payload: dict) -> dict:
    duration = float(payload.get("duration") or 0)
    items = payload.get("highlights", [])
    reals = [h for h in items if h.get("source") != "ambient"]
    reals.sort(key=lambda h: h["ts_start"])

    # 构造需要填充的区间：片头、相邻间隙、片尾
    edges: list[tuple[float, float, str]] = []
    cursor = EDGE
    for h in reals:
        edges.append((cursor, float(h["ts_start"]), h.get("type", "悬念")))
        cursor = float(h["ts_end"])
    if duration > 0:
        edges.append((cursor, duration - EDGE, reals[-1].get("type", "悬念") if reals else "悬念"))

    ambient: list[dict] = []
    seq = 0
    for lo, hi, neighbour_type in edges:
        if hi - lo < MIN_GAP:
            continue
        ts = lo + SPACING
        while ts < hi - WINDOW:
            if not _overlaps(ts, reals):
                # 邻近真实类型 + 轮换，兼顾连贯与多样
                kind = neighbour_type if (seq % 3 == 0 and neighbour_type in CYCLE) \
                    else CYCLE[seq % len(CYCLE)]
                ambient.append(_beat(ts, kind, seq))
                seq += 1
            ts += SPACING

    merged = reals + ambient
    merged.sort(key=lambda h: h["ts_start"])
    payload["highlights"] = merged
    return payload, len(reals), len(ambient)


def main() -> None:
    only = set(sys.argv[1:])
    files = sorted(DATA_DIR.glob("*.json"))
    for path in files:
        ep = path.stem
        if only and ep not in only:
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload, n_real, n_amb = densify(payload)
        path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"{ep}: real={n_real} +ambient={n_amb} -> total={n_real + n_amb}")


if __name__ == "__main__":
    main()
