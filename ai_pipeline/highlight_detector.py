"""高光点识别 —— 用 Doubao 多模态判断每个候选帧是否是高光。

策略：
- 把帧按时间分组（默认 8s 一个窗口），每组取代表帧 + 该窗口字幕
- 一次请求批量评估 N 个窗口（节省 token），要求返回严格 JSON
- 后处理：合并相邻同类高光、过滤低置信度
"""
from __future__ import annotations

import base64
import json
import math
import os
import re
from pathlib import Path
from typing import Any, TypedDict

import httpx

ARK_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"

HIGHLIGHT_TYPES = [
    "家族冲突", "护短撑腰", "身份反转", "年龄反差梗", "打脸爽点", "反杀逆袭",
    "高能冲突", "反派压迫", "搞笑包袱", "离谱吐槽", "颜值名场面", "CP磕糖",
    "泪点破防", "治愈和解", "剧情悬念", "上头追更", "角色高光", "名台词",
]
INTERACTION_MAP = {
    "家族冲突": "燃", "护短撑腰": "护主角", "身份反转": "震惊",
    "年龄反差梗": "离谱", "打脸爽点": "爽", "反杀逆袭": "反杀",
    "高能冲突": "燃", "反派压迫": "屏息", "搞笑包袱": "笑",
    "离谱吐槽": "离谱", "颜值名场面": "封神", "CP磕糖": "磕",
    "泪点破防": "破防", "治愈和解": "治愈", "剧情悬念": "炸裂",
    "上头追更": "上头", "角色高光": "燃", "名台词": "封神",
}
INTERACTION_CHOICES = sorted(set(INTERACTION_MAP.values()))
TYPE_ALIASES = {
    "冲突": "高能冲突",
    "悬念": "剧情悬念",
    "搞笑": "搞笑包袱",
    "爽点": "打脸爽点",
    "打脸": "打脸爽点",
    "反杀": "反杀逆袭",
    "反转": "身份反转",
    "名场面": "角色高光",
    "虐心": "泪点破防",
    "甜蜜": "CP磕糖",
    "高甜": "CP磕糖",
    "磕糖": "CP磕糖",
    "破防": "泪点破防",
    "紧张": "反派压迫",
}


class Window(TypedDict):
    ts: float
    frame_path: str
    subtitle: str


class Highlight(TypedDict):
    ts_start: float
    ts_end: float
    type: str
    interaction: str
    intensity: float
    description: str


def build_windows(frames: list[dict], segments: list[dict], window_size: float = 8.0) -> list[Window]:
    """把帧按 window_size 分桶，每桶取首帧 + 桶内字幕。"""
    if not frames:
        return []
    buckets: dict[int, list[dict]] = {}
    for f in frames:
        idx = int(f["ts"] // window_size)
        buckets.setdefault(idx, []).append(f)

    wins: list[Window] = []
    for idx in sorted(buckets):
        center = idx * window_size + window_size / 2
        rep = buckets[idx][0]
        lo, hi = idx * window_size, (idx + 1) * window_size
        sub = " ".join(s["text"] for s in segments if s["end"] >= lo and s["start"] <= hi)
        wins.append({"ts": center, "frame_path": rep["path"], "subtitle": sub})
    return wins


def _b64_image(path: str) -> str:
    data = Path(path).read_bytes()
    return "data:image/jpeg;base64," + base64.b64encode(data).decode()


SYSTEM_PROMPT = (
    "你是短剧剧情高光编辑，目标是找出适合下发互动的剧情节点。"
    "给你若干个时间窗口（每个含一帧画面 + 同时段台词），请结合画面、台词、角色关系和短剧情绪节奏判断是否为高光。"
    f"高光类型仅限：{HIGHLIGHT_TYPES}。"
    f"interaction 必须且只能从这些短标签中选择：{INTERACTION_CHOICES}；"
    "interaction 不能写成问题、句子或解释。"
    "优先选择和剧情关系强的细分类型，例如身份反转、护短撑腰、打脸爽点、反派压迫、剧情悬念、泪点破防；"
    "只有画面或台词证据不足时才给 is_highlight=false。"
    "字段：window_index(0起), is_highlight(bool), type, interaction, intensity(0~1), "
    "description(28字内, 要写清楚发生了什么剧情), narrative_role(如冲突升级/真相揭露/情绪释放/剧尾钩子), "
    "trigger(高光触发点), evidence(引用台词或画面证据, 30字内)。"
    "同一批窗口请尽量保持类型多样，不要把所有高光都标成同一类。"
    "非高光也要返回一条 is_highlight=false。严格输出 JSON 数组，无解释。"
)


def _normalize_type(value: object) -> str:
    htype = str(value or "").strip()
    htype = TYPE_ALIASES.get(htype, htype)
    if htype not in HIGHLIGHT_TYPES:
        return "角色高光"
    return htype


def _normalize_interaction(value: object, htype: str) -> str:
    text = str(value or "").strip()
    if text in INTERACTION_CHOICES:
        return text
    return INTERACTION_MAP.get(htype, "爽")


def _round_time(value: float, *, duration: float = 0.0) -> float:
    if duration > 0 and value >= duration:
        return math.floor(duration * 100) / 100
    return round(value, 2)


def normalize_highlights(
    hits: list[dict],
    *,
    duration: float | None = None,
    min_duration: float = 1.0,
) -> list[dict]:
    """清洗模型输出：类型归一、互动标签归一、时间范围裁剪。

    这个函数专门兜住大模型的非确定性输出，例如把 interaction 写成一整句、
    ts_end 超过视频时长、旧标签和新标签混用等问题。
    """
    cleaned: list[dict] = []
    video_end = float(duration or 0.0)
    for hit in hits:
        h = dict(hit)
        raw = h.get("raw") if isinstance(h.get("raw"), dict) else {}
        htype = _normalize_type(h.get("type"))
        model_interaction = h.get("interaction")
        interaction = _normalize_interaction(model_interaction, htype)

        try:
            ts_start = max(0.0, float(h.get("ts_start", 0.0)))
            ts_end = max(0.0, float(h.get("ts_end", ts_start + min_duration)))
        except (TypeError, ValueError):
            continue
        if video_end > 0:
            if ts_start >= video_end:
                continue
            ts_end = min(ts_end, video_end)
        if ts_end - ts_start < min_duration:
            ts_end = ts_start + min_duration
            if video_end > 0:
                ts_end = min(ts_end, video_end)
        if ts_end <= ts_start:
            continue

        try:
            intensity = float(h.get("intensity", 0.6))
        except (TypeError, ValueError):
            intensity = 0.6
        intensity = max(0.0, min(1.0, intensity))

        if model_interaction and str(model_interaction).strip() != interaction:
            raw = {**raw, "model_interaction": str(model_interaction).strip()}
        h.update(
            {
                "ts_start": round(ts_start, 2),
                "ts_end": _round_time(ts_end, duration=video_end),
                "type": htype,
                "interaction": interaction,
                "intensity": round(intensity, 3),
                "description": str(h.get("description") or "")[:40],
            }
        )
        if raw:
            h["raw"] = raw
        cleaned.append(h)
    cleaned.sort(key=lambda item: (item["ts_start"], item["ts_end"]))
    return cleaned


def _call_doubao(messages: list[dict]) -> str:
    headers = {
        "Authorization": f"Bearer {os.environ['DOUBAO_API_KEY']}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": os.environ["DOUBAO_ENDPOINT"],
        "messages": messages,
        "temperature": 0.3,
    }
    r = httpx.post(ARK_URL, json=payload, headers=headers, timeout=120)
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def _parse_json_array(text: str) -> list[dict]:
    """容错解析模型返回的 JSON 数组。"""
    text = text.strip()
    text = re.sub(r"^```(?:json)?", "", text).rstrip("`").strip()
    m = re.search(r"\[.*\]", text, re.S)
    if m:
        text = m.group(0)
    return json.loads(text)


def detect_batch(windows: list[Window], batch_size: int = 4) -> list[Highlight]:
    """逐批送给 Doubao；最终合并相邻同类高光。"""
    raw: list[tuple[Window, dict]] = []

    for i in range(0, len(windows), batch_size):
        chunk = windows[i : i + batch_size]
        content: list[dict[str, Any]] = []
        for j, w in enumerate(chunk):
            content.append({"type": "text", "text": f"[窗口{j}] ts={w['ts']:.1f}s 台词：{w['subtitle'] or '（无）'}"})
            content.append({"type": "image_url", "image_url": {"url": _b64_image(w["frame_path"])}})
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": content},
        ]
        try:
            txt = _call_doubao(messages)
            parsed = _parse_json_array(txt)
        except Exception as e:
            print(f"  ! batch {i} failed: {e}")
            continue
        for item in parsed:
            idx = int(item.get("window_index", 0))
            if 0 <= idx < len(chunk):
                raw.append((chunk[idx], item))

    # 过滤 & 转换
    hits: list[Highlight] = []
    for w, item in raw:
        if not item.get("is_highlight"):
            continue
        htype = _normalize_type(item.get("type", "角色高光"))
        intensity = float(item.get("intensity", 0.6))
        if intensity < 0.5:
            continue
        hits.append({
            "ts_start": max(0.0, w["ts"] - 3.0),
            "ts_end": w["ts"] + 4.0,
            "type": htype,
            "interaction": _normalize_interaction(item.get("interaction"), htype),
            "intensity": intensity,
            "description": item.get("description", "")[:40],
            "raw": {
                "source": "doubao_multimodal",
                "window_ts": w["ts"],
                "subtitle": w["subtitle"][:160],
                "narrative_role": item.get("narrative_role", ""),
                "trigger": item.get("trigger", ""),
                "evidence": item.get("evidence", ""),
                "model_interaction": item.get("interaction", ""),
            },
        })

    return _merge_adjacent(normalize_highlights(hits))


def _merge_adjacent(hits: list[Highlight], gap: float = 2.0) -> list[Highlight]:
    if not hits:
        return []
    hits.sort(key=lambda h: h["ts_start"])
    merged: list[Highlight] = [hits[0]]
    for h in hits[1:]:
        last = merged[-1]
        if h["type"] == last["type"] and h["ts_start"] - last["ts_end"] <= gap:
            last["ts_end"] = max(last["ts_end"], h["ts_end"])
            last["intensity"] = max(last["intensity"], h["intensity"])
            if len(h["description"]) > len(last["description"]):
                last["description"] = h["description"]
        else:
            merged.append(h)
    return merged
