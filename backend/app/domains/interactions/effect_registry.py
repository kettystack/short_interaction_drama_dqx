from __future__ import annotations

from dataclasses import dataclass


GOOSE_ACTION = "笑出鹅叫"
GOOSE_BASE_CROWD = 3_246  # 贴近真实感的基准量，避免过大数字破坏沉浸感
LIKE_ACTION = "喜欢"
LIKE_BASE_CROWD = 1_348
POWER_ACTION = "爽"
TEAR_ACTION = "哭"
SHOCK_ACTION = "炸裂"
SUSPENSE_ACTION = "等等"
SWEET_ACTION = "心动"
HEAL_ACTION = "治愈"
GOD_ACTION = "封神"
HYPE_ACTION = "上头"


@dataclass(frozen=True)
class InteractionEffectConfig:
    action: str
    effect: str
    label: str
    related_actions: tuple[str, ...] = ()
    display_base: int = 0


ACTION_EFFECTS: dict[str, InteractionEffectConfig] = {
    GOOSE_ACTION: InteractionEffectConfig(
        action=GOOSE_ACTION,
        effect="goose_laugh",
        label="已有用户笑出鹅叫",
        related_actions=("笑", "笑死", "哈哈", "鹅叫"),
        display_base=GOOSE_BASE_CROWD,
    ),
    LIKE_ACTION: InteractionEffectConfig(
        action=LIKE_ACTION,
        effect="like",
        label="已有用户喜欢",
        related_actions=("点赞", "like", "favorite"),
        display_base=LIKE_BASE_CROWD,
    ),
    POWER_ACTION: InteractionEffectConfig(
        action=POWER_ACTION,
        effect="power_cheer",
        label="已有用户一起上头",
        related_actions=(
            "爽到",
            "打脸",
            "打脸爽点",
            "反杀",
            "反杀逆袭",
            "解气",
            "燃",
            "燃爆",
            "护主角",
            "护短撑腰",
            "高能冲突",
            "角色高光",
        ),
    ),
    TEAR_ACTION: InteractionEffectConfig(
        action=TEAR_ACTION,
        effect="tear_drop",
        label="已有用户破防",
        related_actions=("破防", "泪崩", "心疼", "绷不住", "抱抱", "泪点破防", "虐心"),
    ),
    SHOCK_ACTION: InteractionEffectConfig(
        action=SHOCK_ACTION,
        effect="shock_burst",
        label="已有用户被反转震到",
        related_actions=("神反转", "反转", "身份反转", "震惊", "细思"),
    ),
    SUSPENSE_ACTION: InteractionEffectConfig(
        action=SUSPENSE_ACTION,
        effect="suspense_hold",
        label="已有用户催更",
        related_actions=("别停", "悬念", "剧情悬念", "紧张", "危险", "屏息", "反派压迫"),
    ),
    SWEET_ACTION: InteractionEffectConfig(
        action=SWEET_ACTION,
        effect="heart_bloom",
        label="已有用户磕到了",
        related_actions=("磕", "磕到", "甜", "甜到", "CP磕糖", "高甜", "甜蜜"),
    ),
    HEAL_ACTION: InteractionEffectConfig(
        action=HEAL_ACTION,
        effect="healing_light",
        label="已有用户被治愈",
        related_actions=("暖到", "安心", "治愈和解"),
    ),
    GOD_ACTION: InteractionEffectConfig(
        action=GOD_ACTION,
        effect="god_mode",
        label="已有用户直呼封神",
        related_actions=("名场面", "名台词", "颜值名场面", "绝了"),
    ),
    HYPE_ACTION: InteractionEffectConfig(
        action=HYPE_ACTION,
        effect="hype_burst",
        label="已有用户彻底上头",
        related_actions=("离谱", "离谱吐槽", "上头追更", "继续"),
    ),
}

_ACTION_LOOKUP: dict[str, InteractionEffectConfig] = {}
for config in ACTION_EFFECTS.values():
    _ACTION_LOOKUP[config.action] = config
    for related_action in config.related_actions:
        _ACTION_LOOKUP[related_action] = config


def effect_for_action(action: str, requested_effect: str | None = None) -> str | None:
    if requested_effect:
        return requested_effect
    config = _ACTION_LOOKUP.get(action)
    return config.effect if config else None


def canonical_action(action: str) -> str:
    config = _ACTION_LOOKUP.get(action)
    return config.action if config else action


def actions_for_count(action: str) -> list[str]:
    config = _ACTION_LOOKUP.get(action)
    if not config:
        return [action]
    return sorted({config.action, *config.related_actions})


def display_count_for_action(action: str, count: int) -> int:
    config = _ACTION_LOOKUP.get(action)
    return (config.display_base if config else 0) + count


def label_for_action(action: str) -> str:
    config = _ACTION_LOOKUP.get(action)
    return config.label if config else "已有用户互动"
