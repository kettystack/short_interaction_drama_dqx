"""把现有 highlights/subtitles 转成剧情证据 PlotEvent。

这是 Phase 1/2 的桥接脚本：不重新调用多模态模型，先复用当前高光识别结果，
把 description/raw.evidence/subtitle window 规范化为 data/narrative_events/<episode>.json。
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

EVENT_TYPE_MAP = {
    "反派压迫": "压迫",
    "高能冲突": "压迫",
    "家族冲突": "压迫",
    "反杀逆袭": "反击",
    "打脸爽点": "打脸",
    "护短撑腰": "反击",
    "身份反转": "身份揭露",
    "剧情悬念": "悬念",
    "搞笑包袱": "搞笑",
    "年龄反差梗": "搞笑",
    "泪点破防": "和解",
    "治愈和解": "和解",
    "CP磕糖": "暧昧",
}

NARRATIVE_ROLE_MAP = {
    "压迫": "冲突升级",
    "反击": "情绪释放",
    "身份揭露": "真相揭露",
    "打脸": "情绪释放",
    "反转": "真相揭露",
    "和解": "关系变化",
    "暧昧": "关系变化",
    "悬念": "剧尾钩子",
    "搞笑": "情绪释放",
    "铺垫": "铺垫",
}

CHARACTER_HINTS = [
    "太奶奶", "老祖宗", "向云", "男主", "女主", "主角", "反派", "讨债人", "家族", "小辈",
]


def load_json(path: Path, default: Any) -> Any:
    if not path or not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def convert_highlights_to_events(
    episode_id: str,
    highlights_payload: dict[str, Any] | list[dict[str, Any]],
    subtitles: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    highlights = highlights_payload if isinstance(highlights_payload, list) else highlights_payload.get("highlights", [])
    subtitles = subtitles or []
    events: list[dict[str, Any]] = []
    for index, highlight in enumerate(highlights, start=1):
        ts_start = float(highlight.get("ts_start", 0.0))
        ts_end = float(highlight.get("ts_end", ts_start + 6.0))
        summary = str(highlight.get("description") or highlight.get("summary") or "剧情高光")
        raw = highlight.get("raw") if isinstance(highlight.get("raw"), dict) else {}
        event_type = infer_event_type(str(highlight.get("type", "")), summary)
        dialogue = collect_dialogue_evidence(subtitles, ts_start, ts_end)
        raw_evidence = collect_raw_evidence(raw)
        source_signals = ["highlight_detector"]
        if dialogue:
            source_signals.append("subtitle")
        if raw.get("source"):
            source_signals.append(str(raw["source"]))
        events.append({
            "event_id": f"{episode_id}_{index:04d}",
            "episode_id": episode_id,
            "scene_id": f"{episode_id}_scene_{index:04d}",
            "ts_start": round(ts_start, 2),
            "ts_end": round(ts_end, 2),
            "characters": infer_characters(summary, dialogue, raw_evidence),
            "event_type": event_type,
            "summary": summary,
            "dialogue_evidence": dialogue[:4],
            "visual_evidence": raw_evidence[:4] or [summary],
            "narrative_role": str(raw.get("narrative_role") or NARRATIVE_ROLE_MAP.get(event_type, "铺垫")),
            "confidence": confidence_from_highlight(highlight, bool(dialogue or raw_evidence)),
            "source_signals": sorted(set(source_signals)),
        })
    return {"episode_id": episode_id, "events": events}


def infer_event_type(highlight_type: str, summary: str) -> str:
    if highlight_type in EVENT_TYPE_MAP:
        return EVENT_TYPE_MAP[highlight_type]
    text = highlight_type + summary
    if any(word in text for word in ("身份", "辈分", "揭露", "真相")):
        return "身份揭露"
    if any(word in text for word in ("打脸", "反击", "反杀", "逆袭", "撑腰")):
        return "打脸"
    if any(word in text for word in ("压迫", "威胁", "围堵", "逼")):
        return "压迫"
    if any(word in text for word in ("悬念", "钩子", "追更")):
        return "悬念"
    if any(word in text for word in ("笑", "梗", "离谱")):
        return "搞笑"
    return "铺垫"


def collect_dialogue_evidence(subtitles: list[dict[str, Any]], ts_start: float, ts_end: float) -> list[str]:
    evidence: list[str] = []
    lo = max(0.0, ts_start - 2.0)
    hi = ts_end + 2.0
    for segment in subtitles:
        start = float(segment.get("start", segment.get("ts_start", 0.0)))
        end = float(segment.get("end", segment.get("ts_end", start)))
        if end < lo or start > hi:
            continue
        text = str(segment.get("text", "")).strip()
        if text:
            evidence.append(text[:80])
    return evidence


def collect_raw_evidence(raw: dict[str, Any]) -> list[str]:
    evidence: list[str] = []
    for key in ("evidence", "trigger"):
        value = raw.get(key)
        if isinstance(value, str) and value.strip():
            evidence.append(value.strip()[:80])
    comments = raw.get("evidence_comments")
    if isinstance(comments, list):
        evidence.extend(str(item).strip()[:80] for item in comments if str(item).strip())
    return evidence


def infer_characters(*texts: object) -> list[str]:
    joined = " ".join(_flatten_text(text) for text in texts)
    found = [name for name in CHARACTER_HINTS if name in joined]
    return sorted(set(found))


def confidence_from_highlight(highlight: dict[str, Any], has_evidence: bool) -> float:
    intensity = float(highlight.get("intensity", 0.55))
    confidence = 0.45 + intensity * 0.4
    if has_evidence:
        confidence += 0.1
    return round(max(0.0, min(0.98, confidence)), 3)


def _flatten_text(value: object) -> str:
    if isinstance(value, list):
        return " ".join(_flatten_text(item) for item in value)
    if isinstance(value, dict):
        return " ".join(_flatten_text(item) for item in value.values())
    return str(value)


def episode_id_from_path(path: Path) -> str:
    return re.sub(r"\.json$", "", path.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--episode-id", default="")
    parser.add_argument("--highlights", type=Path, required=True)
    parser.add_argument("--subtitles", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    episode_id = args.episode_id or episode_id_from_path(args.highlights)
    highlights = load_json(args.highlights, {"highlights": []})
    subtitles = load_json(args.subtitles, []) if args.subtitles else []
    payload = convert_highlights_to_events(episode_id, highlights, subtitles)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {len(payload['events'])} plot events -> {args.out}")


if __name__ == "__main__":
    main()
