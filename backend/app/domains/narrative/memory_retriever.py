from __future__ import annotations

from .schemas import PlotEvent


def retrieve_current_events(
    events: list[PlotEvent],
    current_time: float,
    *,
    before: float = 12.0,
    after: float = 4.0,
    min_confidence: float = 0.55,
) -> list[PlotEvent]:
    lo = max(0.0, current_time - before)
    hi = current_time + after
    hits = [
        event
        for event in events
        if event.confidence >= min_confidence and event.ts_end >= lo and event.ts_start <= hi
    ]
    return sorted(hits, key=lambda event: (abs(event.ts_start - current_time), -event.confidence))[:6]


def retrieve_recent_events(
    events: list[PlotEvent],
    current_time: float,
    *,
    lookback: float = 90.0,
    limit: int = 8,
    min_confidence: float = 0.5,
) -> list[PlotEvent]:
    lo = max(0.0, current_time - lookback)
    hits = [
        event
        for event in events
        if event.confidence >= min_confidence and lo <= event.ts_start <= current_time
    ]
    hits = sorted(hits, key=lambda event: (event.ts_start, event.confidence))
    return hits[-limit:]
