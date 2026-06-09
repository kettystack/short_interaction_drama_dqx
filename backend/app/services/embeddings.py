"""轻量语义嵌入：优先调 Doubao Embedding，失败时回退到 char-bigram TF。

设计要点：
- 不引入 sklearn / faiss；纯 numpy 余弦
- 嵌入按 episode_id 缓存到 data/embeddings/index.json，重启复用
- 文本来源：title + description + 该集高光摘要（如果有）
"""
from __future__ import annotations

import json
import math
from collections import Counter
from pathlib import Path
from typing import Iterable

import httpx

from ..config import settings

ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
INDEX_PATH = Path(settings.data_root).resolve() / "embeddings" / "index.json"

_CACHE: dict[str, list[float]] = {}
_LOADED = False
# 第一次调用失败后熔断：后续整段会话只走本地兜底，避免每集 15s × N 的雪崩
_DOUBAO_DISABLED = False


def _load_disk_cache() -> None:
    global _LOADED
    if _LOADED:
        return
    _LOADED = True
    if INDEX_PATH.exists():
        try:
            _CACHE.update(json.loads(INDEX_PATH.read_text(encoding="utf-8")))
        except Exception:
            pass


def _save_disk_cache() -> None:
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    INDEX_PATH.write_text(json.dumps(_CACHE, ensure_ascii=False), encoding="utf-8")


def _fallback_vector(text: str, dim: int = 256) -> list[float]:
    """char-bigram 哈希向量；本地零成本兜底，保证服务可用。"""
    vec = [0.0] * dim
    s = (text or "").strip()
    if not s:
        return vec
    bigrams = [s[i : i + 2] for i in range(len(s) - 1)] or [s]
    cnt = Counter(bigrams)
    for token, c in cnt.items():
        idx = (hash(token) & 0x7FFFFFFF) % dim
        vec[idx] += float(c)
    # L2 归一化
    n = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / n for v in vec]


async def _doubao_embed(text: str) -> list[float] | None:
    """调用 Doubao Embedding；任何错误都吞掉并返回 None，由上层走兜底。"""
    global _DOUBAO_DISABLED
    if _DOUBAO_DISABLED or not settings.doubao_api_key:
        return None
    headers = {
        "Authorization": f"Bearer {settings.doubao_api_key}",
        "Content-Type": "application/json",
    }
    # 使用通用 embedding endpoint 名称；若项目未开通会自动回退
    payload = {"model": "doubao-embedding-text-240715", "input": [text]}
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.post(f"{ARK_BASE_URL}/embeddings", json=payload, headers=headers)
            if r.status_code >= 400:
                _DOUBAO_DISABLED = True  # 熔断：本进程后续直接走本地兜底
                return None
            data = r.json()
            return list(map(float, data["data"][0]["embedding"]))
    except Exception:
        _DOUBAO_DISABLED = True
        return None


async def get_vector(episode_id: str, text: str) -> list[float]:
    _load_disk_cache()
    if episode_id in _CACHE:
        return _CACHE[episode_id]
    vec = await _doubao_embed(text)
    if vec is None:
        vec = _fallback_vector(text)
    _CACHE[episode_id] = vec
    _save_disk_cache()
    return vec


def cosine(a: Iterable[float], b: Iterable[float]) -> float:
    a = list(a)
    b = list(b)
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a)) or 1.0
    nb = math.sqrt(sum(y * y for y in b)) or 1.0
    return dot / (na * nb)


def evict(episode_id: str | None = None) -> None:
    if episode_id is None:
        _CACHE.clear()
    else:
        _CACHE.pop(episode_id, None)
    _save_disk_cache()
