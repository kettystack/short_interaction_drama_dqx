from __future__ import annotations

from .schemas import (
    InteractiveDramaState,
    InteractiveEnding,
    InteractiveGraph,
    InteractiveNode,
    InteractiveOption,
)


STATE_KEYS = (
    "reputation",
    "disguise",
    "power",
    "suspicion",
    "romance",
    "justice",
    "heroine",
    "old_friend",
    "emperor",
    "mastermind",
)

ALLOWED_CONDITION_KEYS = STATE_KEYS + (
    "route_tag",
    "route_tags",
    "flag",
    "flags",
    "missing_flags",
    "any",
    "all",
)


def apply_state_delta(
    state: InteractiveDramaState,
    option: InteractiveOption,
) -> tuple[InteractiveDramaState, dict[str, int]]:
    data = state.model_dump(mode="json")
    changes: dict[str, int] = {}
    for key, delta in option.state_delta.items():
        if key not in STATE_KEYS:
            continue
        before = int(data.get(key, 0))
        after = _clamp(before + int(delta))
        data[key] = after
        changes[key] = after - before
    route_tags = list(data.get("route_tags") or [])
    for tag in option.route_tags:
        if tag and tag not in route_tags:
            route_tags.append(tag)
    data["route_tags"] = route_tags
    flags = dict(data.get("flags") or {})
    for key, value in option.flags_delta.items():
        if key:
            flags[key] = bool(value)
            changes[f"flag:{key}"] = 1 if value else -1
    data["flags"] = flags
    return InteractiveDramaState.model_validate(data), changes


def pick_next_node(
    graph: InteractiveGraph,
    option: InteractiveOption,
    state: InteractiveDramaState,
) -> InteractiveNode | None:
    if option.next_node_id:
        return _node_by_id(graph, option.next_node_id)
    candidates = [
        node
        for node in graph.nodes
        if node.condition and evaluate_condition(state, node.condition)
    ]
    return candidates[0] if candidates else None


def evaluate_condition(state: InteractiveDramaState, condition: dict) -> bool:
    if not condition:
        return True
    for key, expected in condition.items():
        if key == "route_tag":
            if str(expected) not in state.route_tags:
                return False
            continue
        if key == "route_tags":
            expected_tags = expected if isinstance(expected, list) else [expected]
            if not all(str(tag) in state.route_tags for tag in expected_tags):
                return False
            continue
        if key == "flag":
            if not state.flags.get(str(expected), False):
                return False
            continue
        if key == "flags":
            expected_flags = expected if isinstance(expected, list) else [expected]
            if not all(state.flags.get(str(flag), False) for flag in expected_flags):
                return False
            continue
        if key == "missing_flags":
            expected_flags = expected if isinstance(expected, list) else [expected]
            if not any(not state.flags.get(str(flag), False) for flag in expected_flags):
                return False
            continue
        if key == "any":
            branches = expected if isinstance(expected, list) else []
            if not branches or not any(evaluate_condition(state, branch) for branch in branches):
                return False
            continue
        if key == "all":
            branches = expected if isinstance(expected, list) else []
            if not branches or not all(evaluate_condition(state, branch) for branch in branches):
                return False
            continue
        if key in STATE_KEYS and isinstance(expected, dict):
            value = getattr(state, key)
            if "gte" in expected and value < int(expected["gte"]):
                return False
            if "lte" in expected and value > int(expected["lte"]):
                return False
            continue
        if key not in ALLOWED_CONDITION_KEYS:
            return False
    return True


def evaluate_ending(
    graph: InteractiveGraph,
    state: InteractiveDramaState,
) -> InteractiveEnding | None:
    if not graph.endings:
        return None
    for ending in graph.endings:
        condition = ending.condition or {}
        max_key = condition.get("max_key")
        if max_key in STATE_KEYS:
            values = {key: getattr(state, key) for key in STATE_KEYS}
            if values[max_key] == max(values.values()):
                return ending
            continue
        if condition and evaluate_condition(state, condition):
            return ending
    return graph.endings[0]


def build_story_text(
    *,
    node: InteractiveNode,
    option: InteractiveOption,
    state_after: InteractiveDramaState,
    ending: InteractiveEnding | None,
) -> str:
    tags = " / ".join(state_after.route_tags[-3:]) or "未定路线"
    base = (
        f"你选择了“{option.label}”。{option.description}"
        f"这一选择让主角的路线偏向「{tags}」。"
    )
    if ending:
        return f"{base}{ending.summary}"
    next_hint = "下一幕，剧情会继续记住这次选择。"
    if option.next_node_id:
        next_hint = "下一幕会进入新的分支节点，之前的选择会改变可选策略。"
    return f"{base}{node.context}{next_hint}"


def _node_by_id(graph: InteractiveGraph, node_id: str) -> InteractiveNode | None:
    for node in graph.nodes:
        if node.node_id == node_id:
            return node
    return None


def _clamp(value: int) -> int:
    return max(0, min(100, value))
