from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime

from ..narrative.schemas import BranchGenerationContext
from .schemas import StoryChoiceOut, StoryTurnOut


_GENERIC_BAD_PHRASES = (
    "承接“",
    "没有立刻落成一句狠话",
    "众人还没反应过来",
    "全场震惊",
    "霸气反杀",
)


def parse_assistant_turn(
    raw: str,
    *,
    thread_id: str,
    turn_id: str,
    parent_turn_id: str | None,
    context: BranchGenerationContext,
) -> StoryTurnOut:
    obj = _extract_json_object(raw)
    evidence_pool = {
        event.event_id
        for event in [*context.current_scene_events, *context.recent_events]
    }
    evidence_ids = [
        str(item)
        for item in obj.get("evidence_event_ids", [])
        if str(item) in evidence_pool
    ]
    text = _normalize_text(str(obj.get("text", "")))
    choices = _normalize_choices(obj.get("choices", []), action_text=context.selected_choice)
    warnings = _validate_story_output(text, choices)
    if warnings:
        raise ValueError("; ".join(warnings))
    return StoryTurnOut(
        turn_id=turn_id,
        thread_id=thread_id,
        role="assistant_story",
        parent_turn_id=parent_turn_id,
        text=text[:500],
        choices=choices,
        evidence_event_ids=evidence_ids,
        created_at=datetime.utcnow(),
    )


def fallback_assistant_turn(
    *,
    thread_id: str,
    turn_id: str,
    parent_turn_id: str | None,
    action_text: str,
    context: BranchGenerationContext,
) -> StoryTurnOut:
    events = [*context.current_scene_events, *context.recent_events]
    event = events[-1] if events else None
    anchor = event.summary if event else context.episode_title
    direction = (action_text or context.selected_choice or "继续追问").strip()
    text = _fallback_text(anchor=anchor, direction=direction, context=context)
    evidence_ids = [event.event_id] if event else []
    return StoryTurnOut(
        turn_id=turn_id,
        thread_id=thread_id,
        role="assistant_story",
        parent_turn_id=parent_turn_id,
        text=text,
        choices=_fallback_choices(direction),
        evidence_event_ids=evidence_ids,
        created_at=datetime.utcnow(),
    )


def _extract_json_object(raw: str) -> dict:
    text = raw.strip()
    text = re.sub(r"^```(?:json)?", "", text).strip()
    text = re.sub(r"```$", "", text).strip()
    match = re.search(r"\{.*\}", text, re.S)
    if match:
        text = match.group(0)
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("model output is not a JSON object")
    return parsed


def _normalize_text(text: str) -> str:
    text = re.sub(r"\s+", " ", text.replace("\u3000", " ")).strip()
    text = text.strip("`")
    return text[:500]


def _normalize_choices(
    raw_choices: object,
    *,
    action_text: str | None = None,
) -> list[StoryChoiceOut]:
    choices: list[StoryChoiceOut] = []
    seen: set[str] = set()
    if isinstance(raw_choices, list):
        for index, item in enumerate(raw_choices, start=1):
            if isinstance(item, str):
                choice = StoryChoiceOut(choice_id=f"c{len(choices) + 1}", label=_clean_label(item))
            elif isinstance(item, dict):
                choice = StoryChoiceOut(
                    choice_id=f"c{len(choices) + 1}",
                    label=_clean_label(str(item.get("label") or item.get("title") or f"选项{index}")),
                    intent=str(item.get("intent") or "")[:40],
                    preview=str(item.get("preview") or "")[:80],
                    tone=str(item.get("tone") or "")[:16],
                )
            else:
                continue
            if not choice.label or choice.label in seen:
                continue
            if action_text and choice.label == action_text.strip():
                continue
            seen.add(choice.label)
            choices.append(choice)
            if len(choices) >= 3:
                break
    while len(choices) < 3:
        for choice in _fallback_choices(action_text or ""):
            if choice.label not in seen:
                choices.append(
                    StoryChoiceOut(
                        choice_id=f"c{len(choices) + 1}",
                        label=choice.label,
                        intent=choice.intent,
                        preview=choice.preview,
                        tone=choice.tone,
                    )
                )
                seen.add(choice.label)
                break
    return choices[:3]


def _clean_label(text: str) -> str:
    text = re.sub(r"\s+", "", text.strip())
    text = text.strip("。！？,.，、；;：:\"'“”‘’[]【】()（）")
    return text[:12]


def _validate_story_output(text: str, choices: list[StoryChoiceOut]) -> list[str]:
    errors: list[str] = []
    if len(text) < 45:
        errors.append("story text too short")
    if len(text) > 520:
        errors.append("story text too long")
    if any(phrase in text for phrase in _GENERIC_BAD_PHRASES):
        errors.append("story text is too generic")
    if len({choice.label for choice in choices}) < 3:
        errors.append("choices are not diverse")
    return errors


def _fallback_text(
    *,
    anchor: str,
    direction: str,
    context: BranchGenerationContext,
) -> str:
    seed = hashlib.sha1(
        f"{context.episode_id}:{context.current_time}:{direction}:{len(context.branch_history)}".encode(
            "utf-8"
        )
    ).hexdigest()
    variants = [
        (
            f"沿着“{direction}”这条线，{anchor}之后，主角先把声音压低，"
            "让旁人以为事情要缓下去。可他掌心扣着的那枚旧物慢慢露出来，"
            "刚才最笃定的人忽然闭了嘴。下一秒，他把旧物推到灯下，逼对方亲口认出它。"
        ),
        (
            f"{direction}没有马上变成正面冲撞。镜头里，{anchor}留下的疑点被重新拎起，"
            "主角绕到桌侧，故意把半句真相说给最心虚的人听。那人手里的杯沿一抖，"
            "茶水洇开，正好露出藏在纸下的名字。"
        ),
        (
            f"选择“{direction}”后，主角没有追着怒气走，而是先看向身后被牵连的人。"
            f"{anchor}像一根线，把旧账和眼前的局面重新拴在一起。"
            "他抬手关掉吵闹的扩音器，只留一句话：谁先解释这份名单？"
        ),
    ]
    return variants[int(seed[:2], 16) % len(variants)]


def _fallback_choices(direction: str) -> list[StoryChoiceOut]:
    compact = direction.replace(" ", "")
    if any(word in compact for word in ("旧证", "证据", "身份", "真相")):
        return [
            StoryChoiceOut(choice_id="c1", label="当众验旧证", intent="真相揭露", preview="让证物直接改变局势", tone="爽"),
            StoryChoiceOut(choice_id="c2", label="反钓幕后人", intent="悬念升级", preview="顺着假话找出背后的人", tone="悬疑"),
            StoryChoiceOut(choice_id="c3", label="先救身边人", intent="关系变化", preview="把情感选择放在反击之前", tone="温情"),
        ]
    if any(word in compact for word in ("护", "家人", "情感", "升温")):
        return [
            StoryChoiceOut(choice_id="c1", label="护住家人", intent="关系加深", preview="先稳住受伤的一方", tone="温情"),
            StoryChoiceOut(choice_id="c2", label="逼出歉意", intent="情绪释放", preview="让对方为伤害付出代价", tone="爽"),
            StoryChoiceOut(choice_id="c3", label="私下追问", intent="悬念铺垫", preview="把关键误会留到下一场", tone="克制"),
        ]
    return [
        StoryChoiceOut(choice_id="c1", label="正面硬刚", intent="冲突升级", preview="把矛盾推到台前", tone="爽"),
        StoryChoiceOut(choice_id="c2", label="暗中设局", intent="悬念铺垫", preview="让对手自己露出破绽", tone="悬疑"),
        StoryChoiceOut(choice_id="c3", label="关系升温", intent="关系变化", preview="用情感选择改变局势", tone="温情"),
    ]
