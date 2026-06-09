from __future__ import annotations

import json

from ..narrative.schemas import BranchGenerationContext, PlotEvent, RoleCard
from .schemas import StoryThreadOut
from .style_profiles import StoryStyleProfile


SYSTEM_PROMPT = """
你是互动短剧的 AI 编剧引擎，负责把短剧分支写成可连续阅读、可继续选择的剧情对话流。
只能基于输入中的本集摘要、剧情证据链、角色卡、用户分支路径和历史 turns 续写，不要编造未提供的人物关系。
输出必须是严格 JSON 对象，不要 markdown，不要解释。
JSON Schema 语义：
{
  "text": "180字以内续写正文",
  "choices": [
    {"choice_id":"c1","label":"12字以内按钮文案","intent":"剧情意图","preview":"一句话预告","tone":"克制/爽/悬疑/温情"}
  ],
  "evidence_event_ids": ["引用过的 PlotEvent.event_id"]
}
要求：
- choices 必须恰好 3 个，且方向明显不同。
- 正文必须承接 user_action 和 branch_path，不能只是复述剧名或用户选项。
- 每 2-3 句至少包含一个可被拍出来的动作、表情、道具或环境细节。
- 少用“全场震惊”“霸气反杀”“众人哗然”这类总结词。
- 台词不超过全文 35%，但每句台词必须推动关系或信息。
- 最后一行留下具体动作钩子。
- 如果证据链不足，就围绕已有摘要写合理延展，并把 evidence_event_ids 留空。
""".strip()


def _event_to_prompt(event: PlotEvent) -> dict:
    evidence = [*event.dialogue_evidence[:2], *event.visual_evidence[:2]]
    return {
        "event_id": event.event_id,
        "time": [round(event.ts_start, 1), round(event.ts_end, 1)],
        "characters": event.characters[:6],
        "event_type": event.event_type,
        "narrative_role": event.narrative_role,
        "summary": event.summary,
        "evidence": evidence[:4],
        "confidence": round(event.confidence, 2),
    }


def _role_to_prompt(role: RoleCard) -> dict:
    return {
        "name": role.name,
        "aliases": role.aliases[:4],
        "traits": role.traits[:6],
        "relationships": [
            {"target": relation.target, "relation": relation.relation}
            for relation in role.relationships[:6]
        ],
    }


def _build_recent_turns(thread: StoryThreadOut) -> list[dict]:
    turns: list[dict] = []
    for turn in thread.turns[-8:]:
        item = {
            "role": turn.role,
            "selected_choice_id": turn.selected_choice_id,
            "text": turn.text[:360],
        }
        if turn.choices:
            item["choices"] = [
                {
                    "choice_id": choice.choice_id,
                    "label": choice.label,
                    "intent": choice.intent,
                    "preview": choice.preview,
                }
                for choice in turn.choices[:3]
            ]
        turns.append(item)
    return turns


def _build_episode_summary(context: BranchGenerationContext) -> str:
    if context.previous_summary.strip():
        return context.previous_summary.strip()[:900]
    events = [*context.recent_events, *context.current_scene_events]
    seen: set[str] = set()
    summaries: list[str] = []
    for event in sorted(events, key=lambda item: item.ts_start):
        if event.event_id in seen:
            continue
        seen.add(event.event_id)
        summaries.append(event.summary)
    return "；".join(summaries)[:900]


def build_story_chat_messages(
    thread: StoryThreadOut,
    context: BranchGenerationContext,
    style: StoryStyleProfile,
    action_text: str,
    *,
    context_hint: str = "",
) -> list[dict]:
    payload = {
        "style": {
            "code": style.code,
            "name": style.name,
            "prompt": style.prompt,
        },
        "episode": {
            "episode_id": context.episode_id,
            "title": context.episode_title,
            "drama_title": context.drama_title,
            "current_time": round(context.current_time, 1),
            "summary": _build_episode_summary(context),
        },
        "user_action": action_text,
        "user_context_hint": context_hint[:600],
        "branch_path": thread.branch_path,
        "pinned_memory": _build_pinned_memory(thread),
        "recent_turns": _build_recent_turns(thread),
        "role_cards": [_role_to_prompt(role) for role in context.role_cards[:8]],
        "current_scene_events": [_event_to_prompt(event) for event in context.current_scene_events],
        "recent_events": [_event_to_prompt(event) for event in context.recent_events],
        "output_contract": {
            "text_max_chars": 180,
            "choice_count": 3,
            "choice_label_max_chars": 12,
            "choice_id_values": ["c1", "c2", "c3"],
        },
    }
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": "请根据以下剧情上下文继续生成下一轮 assistant_story：\n"
            + json.dumps(payload, ensure_ascii=False, indent=2),
        },
    ]


def _build_pinned_memory(thread: StoryThreadOut) -> list[str]:
    memory: list[str] = []
    for index, item in enumerate(thread.branch_path[-8:], start=1):
        value = item.strip()
        if value:
            memory.append(f"第{index}次用户选择：{value}")
    for turn in thread.turns[-6:]:
        if turn.role != "assistant_story":
            continue
        text = turn.text.replace("\n", " ").strip()
        if text:
            memory.append(f"上一段续写结果：{text[:120]}")
    return memory[-8:]
