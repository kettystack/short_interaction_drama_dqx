from __future__ import annotations

from ...models import Episode, Highlight


def build_aigc_video_prompt(
    *,
    episode: Episode,
    highlight: Highlight | None,
    trigger_type: str,
    user_prompt: str,
    style_code: str,
) -> str:
    highlight_text = ""
    if highlight:
        highlight_text = (
            f"当前高光：{highlight.type}，互动词：{highlight.interaction}，"
            f"剧情：{highlight.description}。"
        )
    instruction = user_prompt.strip() or {
        "boost": "角色获得加速包，镜头表现速度提升，快速推进到救援目标。",
        "revenge": "角色反杀升级，用短剧强节奏完成打脸。",
        "sugar": "角色关系升温，给出甜蜜补帧。",
        "finale": "给出追更钩子和下一集预告感镜头。",
    }.get(trigger_type, "生成一段和当前剧情连贯的短视频插片。")
    return (
        f"剧集：{episode.title}。{highlight_text}"
        f"生成目标：{instruction}"
        f"风格：{style_code}，竖屏短剧，6-8秒，节奏明确，不改变主要人物设定。"
    )

