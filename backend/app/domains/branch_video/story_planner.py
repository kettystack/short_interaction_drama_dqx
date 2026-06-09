from __future__ import annotations

import json
import re

from sqlalchemy.ext.asyncio import AsyncSession

from ..narrative.schemas import BranchGenerationIn
from ..narrative.service import BranchGenerationService
from ..security.cost_tracker import tracked_chat_completion
from .schemas import BranchOptionPlan, BranchStoryPlan, BranchVideoContext


async def build_branch_story(
    db: AsyncSession,
    context: BranchVideoContext,
    option: BranchOptionPlan,
    *,
    user_id: str,
) -> BranchStoryPlan:
    manual_story = await _build_manual_story(
        db,
        context,
        option,
        user_id=user_id,
    )
    if manual_story is not None:
        return manual_story
    generated = await BranchGenerationService(db).generate(
        BranchGenerationIn(
            episode_id=context.episode_id,
            user_id=user_id,
            ts_in_video=context.trigger_ts,
            fork_id=context.fork_id,
            selected_choice=option.label,
            style="竖屏短剧电影感、动作明确、12秒内完成一次起承转合",
        )
    )
    text = generated.text.strip() or option.description
    beats = _split_beats(text)
    return BranchStoryPlan(
        premise=f"在“{context.current_conflict}”之后，主角选择“{option.label}”。",
        opening_continuity="从正片首帧的人物位置、服装、光线和场景连续开始。",
        beats=beats,
        dialogue=[],
        ending_hook=option.expected_hook or "动作完成后停在新的悬念上",
        evidence_event_ids=generated.evidence_event_ids,
        character_constraints=[
            f"主要人物：{','.join(context.active_characters)}"
            if context.active_characters
            else "保持正片现有人物不变",
            "人物身份、关系和性格必须承接正片",
        ],
        negative_constraints=context.forbidden_changes,
    )


async def _build_manual_story(
    db: AsyncSession,
    context: BranchVideoContext,
    option: BranchOptionPlan,
    *,
    user_id: str,
) -> BranchStoryPlan | None:
    manual = context.manual_context or {}
    point = manual.get("point") or {}
    if not point:
        return None
    prompt = {
        "episode_id": context.episode_id,
        "episode_title": context.episode_title,
        "trigger_ts": context.trigger_ts,
        "selected_option": option.model_dump(mode="json"),
        "manual_context": manual,
        "recent_events": context.recent_events,
        "role_cards": context.role_cards,
        "continuity_rules": context.forbidden_changes,
    }
    system = """
你是竖屏短剧分镜编剧。请把人工校准的上下文和用户所选行动写成一段12秒插片规划。
必须从正片首帧的角色位置、服装、道具和光线连续开始；只推进一个明确行动；
第三拍必须使用 ending_bridge 收束，保证插片结束后能自然回到原正片。
剧情要具体，有动作、反应、可见结果和一句短对白，禁止空泛的“局势升级”。
严格输出 JSON，不要 markdown：
{
  "premise":"",
  "opening_continuity":"",
  "beats":["0-3秒动作","3-8秒反应与反转","8-12秒收束"],
  "dialogue":["一句符合人物身份的短对白"],
  "ending_hook":"",
  "evidence_event_ids":[],
  "character_constraints":[],
  "negative_constraints":[]
}
""".strip()
    try:
        raw = await tracked_chat_completion(
            db,
            [
                {"role": "system", "content": system},
                {
                    "role": "user",
                    "content": json.dumps(prompt, ensure_ascii=False),
                },
            ],
            scene="branch_video_manual_story",
            user_id=user_id,
            episode_id=context.episode_id,
            temperature=0.58,
        )
        text = re.sub(r"^```(?:json)?", "", raw.strip()).rstrip("`").strip()
        match = re.search(r"\{.*\}", text, re.S)
        if match:
            text = match.group(0)
        story = BranchStoryPlan.model_validate(json.loads(text))
        if len(story.beats) >= 3:
            story.negative_constraints = list(
                dict.fromkeys(
                    [*story.negative_constraints, *context.forbidden_changes]
                )
            )
            return story
    except Exception:
        pass
    return _manual_story_fallback(context, option)


def _manual_story_fallback(
    context: BranchVideoContext,
    option: BranchOptionPlan,
) -> BranchStoryPlan:
    point = (context.manual_context or {}).get("point") or {}
    before = str(point.get("previous_context") or context.previous_summary)
    next_event = str(point.get("next_main_event") or "原正片下一动作")
    bridge = str(
        point.get("ending_bridge")
        or f"人物视线重新落回现场，衔接“{next_event}”"
    )
    dialogue = str(point.get("dialogue_tone") or "")
    return BranchStoryPlan(
        premise=f"{before}。面对“{context.current_conflict}”，主角选择{option.label}。",
        opening_continuity=str(
            point.get("opening_continuity")
            or "延续正片首帧的人物站位、服装、道具和环境光。"
        ),
        beats=[
            f"主角立即{option.action}，镜头保留现场关键人物",
            f"{option.description}，对方出现清晰可见的反应",
            bridge,
        ],
        dialogue=[dialogue] if dialogue else [],
        ending_hook=bridge,
        character_constraints=[
            (
                "只延续首帧实际可见人物，不强制新增未入镜角色；"
                f"身份参考名单：{','.join(context.active_characters)}"
                if context.active_characters
                else "只延续首帧实际可见人物，不新增陌生角色"
            ),
            "行为必须符合当前权力关系和人物性格",
        ],
        negative_constraints=context.forbidden_changes,
    )


def _split_beats(text: str) -> list[str]:
    parts = [
        item.strip()
        for item in text.replace("！", "。").replace("？", "。").split("。")
        if item.strip()
    ]
    if len(parts) >= 3:
        return parts[:3]
    while len(parts) < 3:
        parts.append(["局势被推进", "行动产生结果", "留下新的钩子"][len(parts)])
    return parts
