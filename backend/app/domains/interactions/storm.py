"""实时"风暴"检测：同一集 + 同一 action 在滑动窗口内计数超过阈值
即广播一条 storm 事件，给端上呈现"全网都在爽"的合鸣效果。

进程内实现，零依赖；如需多副本部署再升级到 Redis Pub/Sub。
"""
from __future__ import annotations

import time
from collections import deque
from typing import Deque, Dict, Tuple

from ...services.ws_manager import ws_manager

# (episode_id, action) -> 最近触发时间戳队列
_BUFFERS: Dict[Tuple[str, str], Deque[float]] = {}
# (episode_id, action) -> 最近一次 storm 广播时间，做冷却
_LAST_FIRE: Dict[Tuple[str, str], float] = {}

WINDOW_SEC = 5.0       # 统计窗口
THRESHOLD = 8          # 同窗口内同 action 触发次数
COOLDOWN_SEC = 10.0    # 风暴广播冷却时间


async def maybe_fire_storm(episode_id: str, action: str) -> None:
    """每次互动 submit 后调用；满足条件则广播一条 storm 事件。"""
    now = time.monotonic()
    key = (episode_id, action)
    buf = _BUFFERS.setdefault(key, deque())
    buf.append(now)
    # 清理窗口外
    while buf and now - buf[0] > WINDOW_SEC:
        buf.popleft()

    count = len(buf)
    if count < THRESHOLD:
        return
    if now - _LAST_FIRE.get(key, 0.0) < COOLDOWN_SEC:
        return
    _LAST_FIRE[key] = now

    # level 1~3：让端上做不同强度的粒子动画
    level = 1 if count < THRESHOLD * 2 else (2 if count < THRESHOLD * 4 else 3)
    await ws_manager.broadcast(
        episode_id,
        {
            "type": "storm",
            "episode_id": episode_id,
            "action": action,
            "count": count,
            "level": level,
            "window_sec": WINDOW_SEC,
        },
    )
