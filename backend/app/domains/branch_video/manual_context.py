from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ...config import settings


def list_manual_branch_points(
    *,
    drama_id: str,
    episode_id: str,
) -> list[dict[str, Any]]:
    payload = _load_payload(drama_id)
    episode = (payload.get("episodes") or {}).get(episode_id, {})
    return [
        point
        for point in episode.get("points") or []
        if isinstance(point, dict)
    ]


def load_manual_branch_context(
    *,
    drama_id: str,
    episode_id: str,
    trigger_source: str,
    trigger_ts: float,
) -> dict[str, Any]:
    payload = _load_payload(drama_id)
    series = payload.get("series") if isinstance(payload, dict) else {}
    episode = (payload.get("episodes") or {}).get(episode_id, {})
    points = episode.get("points") or []
    matched: dict[str, Any] = {}
    distance = float("inf")
    for point in points:
        if not isinstance(point, dict):
            continue
        point_source = str(point.get("trigger_source") or "")
        point_ts = float(point.get("trigger_ts") or 0.0)
        current_distance = abs(point_ts - trigger_ts)
        if point_source and point_source != trigger_source:
            continue
        if current_distance <= 3.0 and current_distance < distance:
            matched = point
            distance = current_distance
    if not matched:
        return {}
    return {
        "version": str(payload.get("version") or "1"),
        "series": series if isinstance(series, dict) else {},
        "episode": {
            key: value
            for key, value in episode.items()
            if key != "points"
        },
        "point": matched,
    }


def _load_payload(drama_id: str) -> dict[str, Any]:
    path = (
        Path(settings.data_root)
        / "branch_context_overrides"
        / f"{drama_id}.json"
    )
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}
