from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..domains.interactions.effect_registry import GOOSE_ACTION, LIKE_ACTION
from ..domains.interactions.realtime import broadcast_presence
from ..domains.interactions.schemas import InteractionIn, InteractionOut, InteractionSummaryOut, InteractionTimelineBucketOut, StoryFeedbackOut
from ..domains.interactions.service import InteractionService
from ..schemas import BranchStoryIn, BranchStoryOut
from ..services.ai_service import generate_branch_story
from ..services.ws_manager import ws_manager

router = APIRouter(prefix="/api/interactions", tags=["interactions"])


@router.post("", response_model=InteractionOut)
async def post_interaction(payload: InteractionIn, db: AsyncSession = Depends(get_db)):
    return await InteractionService(db).submit(payload)


@router.get("/summary/{episode_id}", response_model=InteractionSummaryOut)
async def get_interaction_summary(
    episode_id: str,
    action: str = GOOSE_ACTION,
    highlight_id: int | None = None,
    db: AsyncSession = Depends(get_db),
):
    return await InteractionService(db).summary(episode_id, action, highlight_id)


@router.get("/multi-summary/{episode_id}")
async def get_multi_summary(
    episode_id: str,
    actions: str = f"{GOOSE_ACTION},{LIKE_ACTION}",
    highlight_id: int | None = None,
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    一次返回多个互动动作的汇总数据，减少客户端并行请求数。
    actions 参数为逗号分隔的动作列表，默认返回「笑出鹅叫」和「喜欢」。
    返回 JSON: { "笑出鹅叫": {count, display_count, label}, "喜欢": {...} }
    """
    action_list = [a.strip() for a in actions.split(",") if a.strip()]
    if not action_list:
        action_list = [GOOSE_ACTION, LIKE_ACTION]
    result = await InteractionService(db).multi_summary(episode_id, action_list, highlight_id)
    return {k: v.model_dump() for k, v in result.items()}


@router.get("/timeline/{episode_id}", response_model=list[InteractionTimelineBucketOut])
async def get_interaction_timeline(
    episode_id: str,
    bucket_size: int = 10,
    action: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    return await InteractionService(db).timeline(episode_id, bucket_size, action)


@router.post("/branch", response_model=BranchStoryOut)
async def branch(payload: BranchStoryIn):
    result = await generate_branch_story(payload.context, payload.choice)
    return BranchStoryOut(text=result["text"], choices=result["choices"])


@router.get("/story/{episode_id}", response_model=StoryFeedbackOut)
async def get_story_feedback(
    episode_id: str,
    limit: int = 30,
    db: AsyncSession = Depends(get_db),
):
    """获取该集 AI 续写卡 / 高光卡的点赞数与最近评论。"""
    return await InteractionService(db).story_feedback(episode_id, limit=limit)


@router.websocket("/ws/{episode_id}")
async def ws_room(websocket: WebSocket, episode_id: str):
    await ws_manager.connect(episode_id, websocket)
    await broadcast_presence(episode_id)
    try:
        while True:
            # 心跳；客户端可直接发任意消息保持连接
            await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect(episode_id, websocket)
        await broadcast_presence(episode_id)
