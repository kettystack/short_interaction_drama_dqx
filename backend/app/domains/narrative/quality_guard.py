from __future__ import annotations

import json
import re

from .schemas import BranchChoiceOut, BranchGenerationContext, BranchStoryOut


def parse_branch_story(raw: str, context: BranchGenerationContext, story_id: str) -> BranchStoryOut:
    obj = _extract_json_object(raw)
    evidence_pool = {
        event.event_id
        for event in [*context.current_scene_events, *context.recent_events]
    }
    choices = _normalize_choices(obj.get("choices", []))
    evidence_ids = [str(item) for item in obj.get("evidence_event_ids", []) if str(item) in evidence_pool]
    warnings = [str(item) for item in obj.get("warnings", []) if str(item).strip()]
    if not evidence_ids and evidence_pool:
        warnings.append("模型未引用有效剧情证据，已保留但降低可信度")
    confidence = _clamp_float(obj.get("confidence", 0.65), 0.0, 1.0)
    if not evidence_ids and evidence_pool:
        confidence = min(confidence, 0.62)
    return BranchStoryOut(
        story_id=story_id,
        text=str(obj.get("text", "")).strip()[:500],
        choices=choices,
        evidence_event_ids=evidence_ids,
        confidence=confidence,
        warnings=warnings,
    )


def fallback_branch_story(context: BranchGenerationContext, story_id: str, reason: str) -> BranchStoryOut:
    selected = (context.selected_choice or "继续推进").strip()
    event = (context.current_scene_events or context.recent_events or [None])[-1]
    anchor = event.summary if event else context.episode_title
    if any(word in selected for word in ("身份", "辈分", "亮")):
        text = f"围绕『{anchor}』，她没有急着解释，而是先亮出关键凭证。全场刚要反驳，最懂规矩的人已经变了脸色，局势瞬间倒向她这边。"
    elif any(word in selected for word in ("反击", "硬刚", "打脸")):
        text = f"承接『{anchor}』，主角顺着对方最嚣张的一句话反手设局，等众人以为他要退让时，证据被当场摊开，压迫感直接反转成打脸爽点。"
    else:
        text = f"剧情从『{anchor}』继续推进，主角先稳住局面，再抓住对手话里的破绽，让隐藏矛盾浮出水面，为下一次反转埋下钩子。"
    evidence_ids = [event.event_id for event in context.current_scene_events[:2]]
    if not evidence_ids:
        evidence_ids = [event.event_id for event in context.recent_events[:2]]
    return BranchStoryOut(
        story_id=story_id,
        text=text,
        choices=[
            BranchChoiceOut(choice_id="c1", label="当众反击", intent="打脸爽点", preview="把压迫方的漏洞摆到明面"),
            BranchChoiceOut(choice_id="c2", label="暗中设局", intent="悬念铺垫", preview="先退一步引出幕后线索"),
            BranchChoiceOut(choice_id="c3", label="护住亲近的人", intent="关系变化", preview="用情感选择制造新冲突"),
        ],
        evidence_event_ids=evidence_ids,
        confidence=0.55 if evidence_ids else 0.42,
        warnings=[reason],
    )


def _extract_json_object(raw: str) -> dict:
    text = raw.strip()
    text = re.sub(r"^```(?:json)?", "", text).rstrip("`").strip()
    match = re.search(r"\{.*\}", text, re.S)
    if match:
        text = match.group(0)
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("model output is not a JSON object")
    return parsed


def _normalize_choices(raw_choices: object) -> list[BranchChoiceOut]:
    choices: list[BranchChoiceOut] = []
    if isinstance(raw_choices, list):
        for index, item in enumerate(raw_choices[:3], start=1):
            if isinstance(item, str):
                choices.append(BranchChoiceOut(choice_id=f"c{index}", label=item[:15]))
            elif isinstance(item, dict):
                choices.append(BranchChoiceOut(
                    choice_id=str(item.get("choice_id") or f"c{index}"),
                    label=str(item.get("label") or item.get("title") or f"选项{index}")[:15],
                    intent=str(item.get("intent") or ""),
                    preview=str(item.get("preview") or ""),
                ))
    while len(choices) < 3:
        idx = len(choices) + 1
        choices.append(BranchChoiceOut(choice_id=f"c{idx}", label=f"继续分支{idx}"))
    return choices[:3]


def _clamp_float(value: object, low: float, high: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = low
    return max(low, min(high, number))
