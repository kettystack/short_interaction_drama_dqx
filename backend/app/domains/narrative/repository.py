from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ...config import settings
from .schemas import PlotEvent, RoleCard


class NarrativeRepository:
    def __init__(self, data_root: str | Path | None = None):
        self.data_root = Path(data_root or settings.data_root)

    def load_events(self, episode_id: str) -> list[PlotEvent]:
        path = self.data_root / "narrative_events" / f"{episode_id}.json"
        payload = self._read_json(path, {"events": []})
        raw_events = payload if isinstance(payload, list) else payload.get("events", [])
        events: list[PlotEvent] = []
        for index, item in enumerate(raw_events):
            if not isinstance(item, dict):
                continue
            normalized = self._normalize_event(item, episode_id, index)
            try:
                events.append(PlotEvent.model_validate(normalized))
            except Exception:
                continue
        return sorted(events, key=lambda event: (event.ts_start, event.ts_end))

    def load_role_cards(self, drama_id: str) -> list[RoleCard]:
        path = self.data_root / "role_cards" / f"{drama_id}.json"
        payload = self._read_json(path, {"characters": []})
        raw_cards = payload if isinstance(payload, list) else payload.get("characters", [])
        cards: list[RoleCard] = []
        for item in raw_cards:
            if not isinstance(item, dict):
                continue
            try:
                cards.append(RoleCard.model_validate(item))
            except Exception:
                continue
        return cards

    def load_story_memory(self, drama_id: str) -> dict[str, Any]:
        path = self.data_root / "story_memory" / f"{drama_id}.json"
        payload = self._read_json(path, {})
        return payload if isinstance(payload, dict) else {}

    def previous_summary(self, drama_id: str, episode_id: str) -> str:
        memory = self.load_story_memory(drama_id)
        if isinstance(memory.get("previous_summary"), str):
            return memory["previous_summary"]
        summaries = memory.get("episode_summaries", {})
        if isinstance(summaries, dict):
            return str(summaries.get(episode_id, ""))
        return ""

    def _read_json(self, path: Path, default: Any) -> Any:
        if not path.exists():
            return default
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return default

    def _normalize_event(self, item: dict[str, Any], episode_id: str, index: int) -> dict[str, Any]:
        ts_start = float(item.get("ts_start", 0.0))
        ts_end = float(item.get("ts_end", ts_start))
        if ts_end < ts_start:
            ts_start, ts_end = ts_end, ts_start
        event_id = item.get("event_id") or f"{episode_id}_{index + 1:04d}"
        scene_id = item.get("scene_id") or f"{episode_id}_scene_{index + 1:04d}"
        summary = item.get("summary") or item.get("description") or "未命名剧情事件"
        return {
            "event_id": str(event_id),
            "episode_id": str(item.get("episode_id") or episode_id),
            "scene_id": str(scene_id),
            "ts_start": ts_start,
            "ts_end": ts_end,
            "characters": list(item.get("characters") or []),
            "event_type": item.get("event_type") or "铺垫",
            "summary": str(summary),
            "dialogue_evidence": list(item.get("dialogue_evidence") or []),
            "visual_evidence": list(item.get("visual_evidence") or []),
            "narrative_role": item.get("narrative_role") or "铺垫",
            "confidence": float(item.get("confidence", 0.5)),
            "source_signals": list(item.get("source_signals") or []),
        }
