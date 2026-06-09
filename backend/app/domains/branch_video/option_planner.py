from __future__ import annotations

import json
import re

from sqlalchemy.ext.asyncio import AsyncSession

from ..security.cost_tracker import tracked_chat_completion
from .schemas import BranchOptionPlan, BranchOptionPlanSet, BranchVideoContext


async def plan_branch_options(
    db: AsyncSession,
    context: BranchVideoContext,
    *,
    option_count: int = 3,
    user_id: str = "anon",
) -> BranchOptionPlanSet:
    manual_plan = _manual_plan(context, option_count=option_count)
    if manual_plan is not None:
        return manual_plan
    system = """
你是互动短剧分支策划。根据剧情证据生成一个自然问题和三个方向明显不同的选项。
只能使用给定人物和冲突，不能新增会破坏主线的身份、地点或关系。
每个选项必须适合在12秒竖屏短片中表现，并能在结尾无缝回到原正片。
严格输出 JSON：
{"question":"20字以内问题","options":[
{"option_key":"A","label":"15字以内","description":"一句预告","action":"核心动作","emotion":"情绪","relationship_change":"","expected_hook":"","preview":""}
]}
不要 markdown。
""".strip()
    try:
        raw = await tracked_chat_completion(
            db,
            [
                {"role": "system", "content": system},
                {
                    "role": "user",
                    "content": json.dumps(context.model_dump(mode="json"), ensure_ascii=False),
                },
            ],
            scene="branch_video_option_planning",
            user_id=user_id,
            episode_id=context.episode_id,
            temperature=0.72,
        )
        parsed = _extract_object(raw)
        options = [
            BranchOptionPlan.model_validate(item)
            for item in list(parsed.get("options") or [])[:option_count]
        ]
        if len(options) >= 2:
            return BranchOptionPlanSet(
                question=str(parsed.get("question") or _fallback_question(context))[:80],
                options=options,
            )
    except Exception:
        pass
    return _fallback_plan(context, option_count=option_count)


def plans_from_configured_branches(context: BranchVideoContext, branches) -> BranchOptionPlanSet:
    manual_plan = _manual_plan(context, option_count=3)
    if manual_plan is not None:
        return manual_plan
    options = []
    for index, branch in enumerate(branches[:3]):
        label = branch.choice_label.strip()
        options.append(
            BranchOptionPlan(
                option_key=chr(ord("A") + index),
                label=label,
                description=(branch.description or f"沿着“{label}”推进剧情").strip(),
                action=label,
                emotion=_emotion_for_text(label),
                expected_hook="完成一次明确行动后留下新的悬念",
                preview=(branch.description or label).strip(),
            )
        )
    return BranchOptionPlanSet(
        question=_fallback_question(context),
        options=options,
    )


def plan_from_custom_prompt(prompt: str, *, order_idx: int) -> BranchOptionPlan:
    value = prompt.strip()
    label = value if len(value) <= 15 else f"{value[:13]}…"
    return BranchOptionPlan(
        option_key=f"custom_{order_idx}",
        label=label,
        description=value,
        action=value,
        emotion=_emotion_for_text(value),
        expected_hook="执行用户指定行动，并留下可回归主线的悬念",
        preview=value,
    )


def _fallback_plan(context: BranchVideoContext, *, option_count: int) -> BranchOptionPlanSet:
    conflict = context.current_conflict or context.episode_title
    templates = [
        ("A", "正面迎击扭转局面", "抓住对方破绽，当场完成一次有力反制", "正面反击", "燃"),
        ("B", "暂时示弱暗中设局", "先稳住局势，再留下一个反转证据", "暗中布局", "悬疑"),
        ("C", "护住同伴寻找援手", "优先保护重要的人，让关系推动下一步", "保护与求助", "情感"),
    ]
    return BranchOptionPlanSet(
        question=f"面对“{conflict[:22]}”，接下来该怎么做？",
        options=[
            BranchOptionPlan(
                option_key=key,
                label=label,
                description=description,
                action=action,
                emotion=emotion,
                expected_hook="行动完成后留下新的剧情钩子",
                preview=description,
            )
            for key, label, description, action, emotion in templates[:option_count]
        ],
    )


def _manual_plan(
    context: BranchVideoContext,
    *,
    option_count: int,
) -> BranchOptionPlanSet | None:
    point = (context.manual_context or {}).get("point") or {}
    raw_options = point.get("options") or []
    if len(raw_options) < 2:
        return None
    options: list[BranchOptionPlan] = []
    for index, item in enumerate(raw_options[:option_count]):
        if not isinstance(item, dict):
            continue
        label = str(item.get("label") or "").strip()
        if not label:
            continue
        options.append(
            BranchOptionPlan(
                option_key=str(item.get("option_key") or chr(ord("A") + index)),
                label=label,
                description=str(item.get("description") or label),
                action=str(item.get("action") or label),
                emotion=str(item.get("emotion") or _emotion_for_text(label)),
                relationship_change=str(item.get("relationship_change") or ""),
                expected_hook=str(
                    item.get("expected_hook")
                    or point.get("ending_bridge")
                    or "留下悬念后回到正片"
                ),
                preview=str(item.get("preview") or item.get("description") or label),
            )
        )
    if len(options) < 2:
        return None
    return BranchOptionPlanSet(
        question=str(point.get("question") or _fallback_question(context))[:80],
        options=options,
    )


def _fallback_question(context: BranchVideoContext) -> str:
    conflict = context.current_conflict or context.highlight_summary
    if conflict:
        return f"面对“{conflict[:24]}”，主角要怎么应对？"
    return "关键局面已经出现，接下来要怎么面对？"


def _emotion_for_text(text: str) -> str:
    if any(word in text for word in ("反击", "硬刚", "迎战", "对峙")):
        return "燃"
    if any(word in text for word in ("暗", "装", "设局", "调查")):
        return "悬疑"
    if any(word in text for word in ("护", "救", "求助", "安抚")):
        return "情感"
    return "紧张"


def _extract_object(raw: str) -> dict:
    text = re.sub(r"^```(?:json)?", "", raw.strip()).rstrip("`").strip()
    match = re.search(r"\{.*\}", text, re.S)
    if match:
        text = match.group(0)
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError("option plan is not an object")
    return value
