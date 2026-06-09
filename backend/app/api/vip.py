from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import Episode
from ..schemas import VipBenefitOut, VipProfileOut
from .episodes import episode_to_out

router = APIRouter(prefix="/api/vip", tags=["vip"])

VIP_BENEFITS = [
    VipBenefitOut(code="4k", title="4K 蓝光", subtitle="高清画质"),
    VipBenefitOut(code="dolby", title="杜比音效", subtitle="沉浸声场"),
    VipBenefitOut(code="no_ads", title="免广告", subtitle="流畅观看"),
    VipBenefitOut(code="devices", title="4 端通用", subtitle="跨端同步"),
    VipBenefitOut(code="ai_branch", title="AI 续写", subtitle="专属互动"),
    VipBenefitOut(code="early_access", title="抢先看", subtitle="提前解锁"),
    VipBenefitOut(code="skin", title="专属皮肤", subtitle="会员标识"),
    VipBenefitOut(code="gift", title="会员礼包", subtitle="每月领取"),
]


@router.get("/profile", response_model=VipProfileOut)
async def vip_profile(
    user_id: str = "anon",
    limit: int = 8,
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(Episode).order_by(Episode.drama_id, Episode.episode_no)
    )
    episodes = list(res.scalars().all())[: max(1, min(limit, 20))]
    short_id = user_id[-4:] if len(user_id) >= 4 else user_id
    return VipProfileOut(
        user_id=user_id,
        display_name=f"用户{short_id}",
        vip_level=3,
        vip_badge="SVIP3",
        goose_coins=0,
        diamonds=0,
        benefits=VIP_BENEFITS,
        vip_episodes=[episode_to_out(ep) for ep in episodes],
    )