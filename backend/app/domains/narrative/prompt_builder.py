from __future__ import annotations

import json

from .schemas import BranchGenerationContext


SYSTEM_PROMPT = """
你是短剧互动分支编剧。你只能基于给定的剧情证据链续写，不要编造未提供的人物关系。
输出必须是严格 JSON 对象，不要 markdown，不要解释。
JSON Schema 语义：
{
  "text": "180字以内续写正文，节奏快，有短剧爽点和反转",
  "choices": [
    {"choice_id":"c1","label":"15字以内按钮文案","intent":"剧情意图","preview":"一句话预告"}
  ],
  "evidence_event_ids": ["引用过的 PlotEvent.event_id"],
  "confidence": 0.0到1.0,
  "warnings": ["如果证据不足，写明原因"]
}
要求：
- choices 必须恰好 3 个，且方向明显不同。
- evidence_event_ids 只能来自输入里的 event_id。
- 如果证据很少，仍要输出可用续写，但 confidence 降低并给 warnings。
""".strip()


def build_branch_generation_messages(context: BranchGenerationContext) -> list[dict]:
    payload = context.model_dump(mode="json")
    user_content = json.dumps(payload, ensure_ascii=False, indent=2)
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"请根据以下 BranchGenerationContext 生成互动分支续写：\n{user_content}"},
    ]
