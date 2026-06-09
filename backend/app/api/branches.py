"""剧情分支播放 API。

数据模型见 models.BranchFork / Branch。

接口：
- GET  /api/branches/forks/{episode_id}        列出该集所有分叉点（含分支选项）
- POST /api/branches/seed                       从 JSON 配置批量导入分叉与分支
"""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..config import settings
from ..database import get_db
from ..models import Branch, BranchFork, Episode

router = APIRouter(prefix="/api/branches", tags=["branches"])


# ============= Schemas =============

class BranchOut(BaseModel):
    id: int
    fork_id: int
    choice_label: str
    video_url: str
    duration: float
    order_idx: int
    description: str
    next_fork_id: int | None

    class Config:
        from_attributes = True


class ForkOut(BaseModel):
    id: int
    episode_id: str
    ts_in_video: float
    parent_branch_id: int | None
    prompt_text: str
    branches: list[BranchOut]

    class Config:
        from_attributes = True


# ============= Endpoints =============

@router.get("/forks/{episode_id}", response_model=list[ForkOut])
async def list_forks(episode_id: str, db: AsyncSession = Depends(get_db)):
    res = await db.execute(
        select(BranchFork)
        .where(BranchFork.episode_id == episode_id)
        .options(selectinload(BranchFork.branches))
        .order_by(BranchFork.ts_in_video)
    )
    forks = res.scalars().all()
    # 每个 fork 的 branches 按 order_idx 排序
    for f in forks:
        f.branches.sort(key=lambda b: b.order_idx)
    return forks


@router.post("/seed")
async def seed_branches(db: AsyncSession = Depends(get_db)):
    """从 data/branches.json 批量导入分支配置。

    JSON 格式：
    {
      "forks": [
        {
          "episode_id": "ep_063",
          "ts_in_video": 56.0,
          "parent_branch_id": null,
          "prompt_text": "向云要怎么应对？",
          "branches": [
            {
              "choice_label": "假意接钱伺机反击",
              "video_url": "/videos/branches/ep_063_b1.mp4",
              "duration": 60.0,
              "order_idx": 0,
              "description": "佯装贪财，扣腕反制"
            },
            ...
          ]
        }
      ]
    }
    """
    path = Path(settings.data_root) / "branches.json"
    if not path.exists():
        raise HTTPException(404, f"no branches config: {path}")

    payload = json.loads(path.read_text(encoding="utf-8"))

    # 校验所有 episode_id 存在
    episode_ids = {f["episode_id"] for f in payload.get("forks", [])}
    for eid in episode_ids:
        if not await db.get(Episode, eid):
            raise HTTPException(400, f"episode not exists: {eid}")

    # 清空旧的（先 branches 后 forks，避免外键）
    await db.execute(Branch.__table__.delete())
    await db.execute(BranchFork.__table__.delete())
    await db.flush()

    fork_count = 0
    branch_count = 0
    for f in payload.get("forks", []):
        fork = BranchFork(
            episode_id=f["episode_id"],
            ts_in_video=float(f["ts_in_video"]),
            parent_branch_id=f.get("parent_branch_id"),
            prompt_text=f.get("prompt_text", "接下来怎么走？"),
        )
        db.add(fork)
        await db.flush()  # 拿到 fork.id
        fork_count += 1

        for b in f.get("branches", []):
            db.add(Branch(
                fork_id=fork.id,
                choice_label=b["choice_label"],
                video_url=b["video_url"],
                duration=float(b.get("duration", 0)),
                order_idx=int(b.get("order_idx", 0)),
                description=b.get("description", ""),
                next_fork_id=b.get("next_fork_id"),
            ))
            branch_count += 1

    await db.commit()
    return {"forks": fork_count, "branches": branch_count}
