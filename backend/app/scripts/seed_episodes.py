"""一次性脚本：把 beipaixunbao 文件夹下的 mp4 灌入 episodes 表。

用法：
    cd backend && python -m app.scripts.seed_episodes
"""
import asyncio
import re
from pathlib import Path

from sqlalchemy import select

from ..config import settings
from ..database import SessionLocal, init_db
from ..models import Episode

DRAMA_ID = "beipaixunbao"
DRAMA_TITLE = "北派寻宝笔记"

EP_RE = re.compile(r"第(\d+)集")


async def main() -> None:
    await init_db()
    video_dir = Path(settings.video_root).resolve()
    files = sorted(video_dir.glob("第*.mp4"))
    print(f"扫描到 {len(files)} 个剧集文件 @ {video_dir}")

    async with SessionLocal() as db:
        for f in files:
            m = EP_RE.search(f.name)
            if not m:
                continue
            no = int(m.group(1))
            ep_id = f"ep_{no:03d}"
            exist = await db.get(Episode, ep_id)
            if exist:
                continue
            db.add(
                Episode(
                    id=ep_id,
                    drama_id=DRAMA_ID,
                    title=f"{DRAMA_TITLE} 第{no}集",
                    episode_no=no,
                    video_url=f"/videos/{f.name}",
                )
            )
            print(f"  + {ep_id}: {f.name}")
        await db.commit()
    print("done.")


if __name__ == "__main__":
    asyncio.run(main())
