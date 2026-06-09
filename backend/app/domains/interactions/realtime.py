from .schemas import InteractionOut
from ...services.ws_manager import ws_manager


async def broadcast_interaction(event: InteractionOut) -> None:
    message = event.model_dump(mode="json")
    message["type"] = "interaction"
    message["ts"] = event.ts_in_video
    await ws_manager.broadcast(event.episode_id, message)


async def broadcast_presence(episode_id: str) -> None:
    await ws_manager.broadcast(
        episode_id,
        {
            "type": "presence",
            "episode_id": episode_id,
            "online_count": ws_manager.room_size(episode_id),
        },
    )
