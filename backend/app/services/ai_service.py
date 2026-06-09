"""Doubao (Volcengine Ark) 调用封装。

仅用于后端在线推理：
- 高光点二次校准（可选）
- 剧情分支续写
"""
from __future__ import annotations

from typing import Any

import httpx

from ..config import settings


ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"


def _first_present(*values: str | None) -> str:
    for value in values:
        if value and value.strip():
            return value.strip()
    return ""


def chat_model_name() -> str:
    """当前文本生成模型/Ark endpoint。

    优先级：
    1. STORY_CHAT_*：剧情续写专用
    2. ARK_*：通用火山方舟
    3. AIGC_VIDEO_MULTIMODAL_*：当前仓库已有的 Doubao-Seed-2.0-lite 配置
    4. DOUBAO_*：项目旧配置
    """
    return _first_present(
        settings.story_chat_endpoint,
        settings.ark_endpoint,
        settings.aigc_video_multimodal_endpoint,
        settings.doubao_endpoint,
    )


def chat_provider_name() -> str:
    return "doubao-ark"


def _chat_api_key() -> str:
    return _first_present(
        settings.story_chat_api_key,
        settings.ark_api_key,
        settings.aigc_video_multimodal_api_key,
        settings.doubao_api_key,
    )


def _chat_base_url() -> str:
    return _first_present(
        settings.story_chat_base_url,
        settings.ark_base_url,
        ARK_BASE_URL,
    ).rstrip("/")


async def chat_completion(
    messages: list[dict],
    temperature: float = 0.7,
    *,
    max_tokens: int | None = None,
    response_format: dict[str, Any] | None = None,
) -> str:
    """调用 Ark Chat Completion，返回 assistant 文本。

    Ark 的 chat completions 与 OpenAI 风格兼容；这里保持轻封装，避免业务层
    直接接触密钥、endpoint 和 HTTP 细节。
    """
    api_key = _chat_api_key()
    model = chat_model_name()
    if not api_key or not model:
        raise RuntimeError(
            "STORY_CHAT_API_KEY/ENDPOINT 或 ARK_API_KEY/ENDPOINT 未配置；"
            "也可复用 DOUBAO_* / AIGC_VIDEO_MULTIMODAL_*"
        )

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
    }
    if max_tokens is not None:
        payload["max_completion_tokens"] = max_tokens
    if response_format is not None:
        payload["response_format"] = response_format

    async with httpx.AsyncClient(timeout=settings.story_chat_timeout_seconds) as client:
        r = await client.post(
            f"{_chat_base_url()}/chat/completions",
            json=payload,
            headers=headers,
        )
        if r.status_code == 400 and (response_format is not None or max_tokens is not None):
            # Some Ark endpoints lag on optional OpenAI-compatible fields. Keep
            # the model call alive and let the JSON parser/repair layer handle
            # format drift instead of falling straight to scripted fallback.
            retry_payload = dict(payload)
            retry_payload.pop("response_format", None)
            retry_payload.pop("max_completion_tokens", None)
            r = await client.post(
                f"{_chat_base_url()}/chat/completions",
                json=retry_payload,
                headers=headers,
            )
        r.raise_for_status()
        data = r.json()
        return str(data["choices"][0]["message"]["content"])


def _fallback_branch_story(context: str, choice: str | None = None) -> dict:
    selected = (choice or "自由发挥").strip()
    if any(word in selected for word in ("辈分", "身份", "亮明")):
        text = (
            "她抬手亮出祖传信物，语气不重，却让满堂瞬间安静。"
            "最先反应过来的长辈脸色煞白，当场改口叫太奶奶。"
            "那些刚才起哄的人想退，她却已经点名要查清是谁在背后挑事。"
        )
        choices = ["立刻重整家规", "追查幕后黑手", "先安抚受委屈的孙辈"]
    elif any(word in selected for word in ("糊涂", "套", "幕后")):
        text = (
            "她故意装作没听懂，顺着对方的话追问了两句。"
            "那人越说越急，竟把早就准备好的假证据抖了出来。"
            "她这才笑着抬眼，轻轻一句话，就把局势反扣回对方身上。"
        )
        choices = ["公开假证据", "反向设局钓人", "带家人悄悄离场"]
    else:
        text = (
            "局面僵住的一刻，她没有急着解释，而是先护住被为难的家人。"
            "等众人以为她退让时，她反手拿出关键证据。"
            "刚才最嚣张的人脸色骤变，全场风向瞬间倒向她这边。"
        )
        choices = ["当众公布证据", "逼对方公开道歉", "顺势接管家族事务"]
    return {"text": text, "choices": choices}


async def generate_branch_story(
    context: str,
    choice: str | None = None,
    *,
    episode_summary: str | None = None,
    role_card: str | None = None,
    style: str = "节奏紧凑、爽点密集、情绪张力强",
) -> dict:
    """返回 {text: str, choices: list[str]}。

    升级点（相比 v1）：
    - system 加角色卡 / 前情摘要 / 风格约束，避免跳戏
    - 加 1 条 few-shot 示范，稳定 JSON 输出格式与质量
    """
    import json
    import re

    system_lines = [
        "你是短剧编剧 AI。任务：根据『已发生剧情 + 用户选择的方向』，"
        "输出一段 ≤200 字的精彩续写，并给出 3 个截然不同的下一步选项（每个 ≤15 字）。",
        f"风格约束：{style}。要求：不跳戏、保证与上文人物设定一致。",
        '输出严格 JSON，不要任何 markdown 或说明：{"text":"...","choices":["A","B","C"]}',
    ]
    if role_card:
        system_lines.append(f"角色卡：{role_card}")
    if episode_summary:
        system_lines.append(f"本集前情摘要：{episode_summary}")

    few_shot_user = (
        "已发生剧情：男主被讨债人围在工厂门口。\n\n"
        "用户选择的方向：反击"
    )
    few_shot_assistant = (
        '{"text":"男主咧嘴一笑，反手扣住为首者腕骨一拧，'
        '膝盖顶上对方腰眼，三人成品字阵被他一一撂倒。他拍拍沾血的拳头：'
        '欠的钱我会还，但今天先把你们送医院。",'
        '"choices":["连夜跑路投奔旧友","报警留下证据","趁势反向逼问幕后老板"]}'
    )

    user_content = f"已发生剧情：\n{context}\n\n用户选择的方向：{choice or '自由发挥'}"
    try:
        raw = await chat_completion(
            [
                {"role": "system", "content": "\n".join(system_lines)},
                {"role": "user", "content": few_shot_user},
                {"role": "assistant", "content": few_shot_assistant},
                {"role": "user", "content": user_content},
            ],
            temperature=0.85,
        )
    except Exception:
        return _fallback_branch_story(context, choice)
    # 容错：提取第一个 JSON 对象
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if m:
        try:
            obj = json.loads(m.group(0))
            return {
                "text": str(obj.get("text", raw)).strip(),
                "choices": [str(c) for c in obj.get("choices", [])][:3],
            }
        except json.JSONDecodeError:
            pass
    return {"text": raw.strip(), "choices": []}
