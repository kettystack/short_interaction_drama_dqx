from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ...config import settings
from .schemas import StoryThreadOut, StoryTurnOut


class StoryChatRepository:
    def __init__(self, data_root: str | Path | None = None):
        self.root = Path(data_root or settings.data_root) / "story_chat_threads"

    def get_thread(self, thread_id: str) -> StoryThreadOut | None:
        path = self._path(thread_id)
        if not path.exists():
            return None
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            return StoryThreadOut.model_validate(payload)
        except (OSError, json.JSONDecodeError, ValueError):
            return None

    def save_thread(self, thread: StoryThreadOut) -> StoryThreadOut:
        self.root.mkdir(parents=True, exist_ok=True)
        payload: dict[str, Any] = thread.model_dump(mode="json")
        self._path(thread.thread_id).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return thread

    def append_turns(self, thread: StoryThreadOut, turns: list[StoryTurnOut]) -> StoryThreadOut:
        thread.turns.extend(turns)
        return self.save_thread(thread)

    def _path(self, thread_id: str) -> Path:
        safe = "".join(ch for ch in thread_id if ch.isalnum() or ch in ("_", "-"))
        return self.root / f"{safe}.json"

