"""根据 narrative_events 聚合轻量 story memory。

用法：
  python story_memory_builder.py --drama-id shibasuitainainai \
    --events-dir ../data/narrative_events --out ../data/story_memory/shibasuitainainai.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_events(events_dir: Path, prefix: str = "") -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for path in sorted(events_dir.glob("*.json")):
        if prefix and not path.stem.startswith(prefix):
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        raw_events = payload if isinstance(payload, list) else payload.get("events", [])
        events.extend(item for item in raw_events if isinstance(item, dict))
    return sorted(events, key=lambda item: (str(item.get("episode_id", "")), float(item.get("ts_start", 0.0))))


def build_story_memory(drama_id: str, events: list[dict[str, Any]], max_summary_events: int = 20) -> dict[str, Any]:
    top_events = sorted(events, key=lambda item: float(item.get("confidence", 0.0)), reverse=True)[:max_summary_events]
    previous_summary = "；".join(str(item.get("summary", "")).strip() for item in top_events if item.get("summary"))[:1200]
    episode_summaries: dict[str, str] = {}
    for item in events:
        episode_id = str(item.get("episode_id", ""))
        if not episode_id:
            continue
        text = str(item.get("summary", "")).strip()
        if not text:
            continue
        episode_summaries.setdefault(episode_id, "")
        if len(episode_summaries[episode_id]) < 600:
            episode_summaries[episode_id] += ("；" if episode_summaries[episode_id] else "") + text
    return {
        "drama_id": drama_id,
        "previous_summary": previous_summary,
        "episode_summaries": episode_summaries,
        "event_count": len(events),
        "source": "story_memory_builder",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--drama-id", required=True)
    parser.add_argument("--events-dir", type=Path, required=True)
    parser.add_argument("--prefix", default="", help="只聚合指定 episode_id 前缀，例如 sbtnn_")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    events = load_events(args.events_dir, args.prefix)
    memory = build_story_memory(args.drama_id, events)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(memory, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote story memory: events={len(events)} -> {args.out}")


if __name__ == "__main__":
    main()
