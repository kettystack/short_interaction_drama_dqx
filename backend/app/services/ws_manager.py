from collections import defaultdict
from typing import Dict, Set

from fastapi import WebSocket


class WSManager:
    """按 episode_id 维度做广播；用于同一集观众的互动飘屏。"""

    def __init__(self) -> None:
        self.rooms: Dict[str, Set[WebSocket]] = defaultdict(set)

    async def connect(self, episode_id: str, ws: WebSocket) -> int:
        await ws.accept()
        self.rooms[episode_id].add(ws)
        return self.room_size(episode_id)

    def disconnect(self, episode_id: str, ws: WebSocket) -> int:
        self.rooms[episode_id].discard(ws)
        if not self.rooms[episode_id]:
            self.rooms.pop(episode_id, None)
        return self.room_size(episode_id)

    def room_size(self, episode_id: str) -> int:
        return len(self.rooms.get(episode_id, set()))

    async def broadcast(self, episode_id: str, message: dict) -> None:
        dead: list[WebSocket] = []
        for ws in list(self.rooms.get(episode_id, set())):
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(episode_id, ws)


ws_manager = WSManager()
