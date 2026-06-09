from __future__ import annotations

from ...config import settings
from .schemas import AigcGenerationContext, VideoInsertIntent


_TRIGGER_PRESETS = {
    "boost": ("加速推进", "紧张高能", "快速推进到下一剧情节点"),
    "revenge": ("反杀推进", "爽感爆发", "让角色完成短暂蓄势和反击动机"),
    "sugar": ("情感升温", "甜蜜柔和", "用细节补足两人关系变化"),
    "finale": ("悬念预告", "悬疑期待", "给出下一段剧情钩子"),
}


def plan_video_intent(
    *,
    context: AigcGenerationContext,
    user_prompt: str,
    duration_seconds: float | None = None,
) -> VideoInsertIntent:
    duration = duration_seconds or settings.aigc_insert_duration_seconds
    action, emotion, default_goal = _TRIGGER_PRESETS.get(
        context.trigger_type,
        ("剧情推进", "短剧高能", "生成一段承上启下的剧情过渡"),
    )
    highlight_text = context.highlight_text or _nearby_context_text(context)
    goal = user_prompt.strip() or default_goal
    must_include = [
        context.episode_title,
        "延续当前人物、服装、场景和光线",
        "首帧从当前画面自然开始",
        "结尾为正片继续播放留出自然剪辑点",
    ]
    if highlight_text:
        must_include.append(highlight_text)
    must_avoid = [
        "不要出现其他剧集人物",
        "不要切换成完全无关场景",
        "不要改变主要人物关系",
        "不要出现片头、片尾、字幕卡或海报式画面",
    ]
    prompt = (
        f"为竖屏短剧《{context.episode_title}》生成 {duration:.0f} 秒加速包插片。"
        f"当前目标：{goal}。"
        f"剧情上下文：{highlight_text or '当前剧情进入关键分支点'}。"
        f"动作：{action}；情绪：{emotion}；镜头：节奏明确、运动自然、短剧电影感。"
        "必须严格以输入的正片首帧作为起点，保持其中人物的中国人面孔、年龄、发型、服装、场景和光线连续。"
        "只让当前人物完成一个幅度适中的推进动作，结尾留出可剪辑的稳定画面。"
        "不要引入陌生人物，不要跳到其他剧集，不要改变主线设定。"
    )
    return VideoInsertIntent(
        trigger_type=context.trigger_type,
        action=action,
        emotion=emotion,
        duration_seconds=duration,
        must_include=must_include,
        must_avoid=must_avoid,
        prompt=prompt,
    )


def _nearby_context_text(context: AigcGenerationContext) -> str:
    for item in context.nearby_highlights:
        text = item.get("description") or item.get("type") or ""
        if text:
            return str(text)
    for item in context.nearby_events:
        text = item.get("summary") or item.get("description") or item.get("event") or ""
        if text:
            return str(text)
    return ""
