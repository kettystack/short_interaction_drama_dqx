#!/usr/bin/env python3
"""Audit and optionally normalize highlight JSON files.

This script is intentionally model-free: it checks the persisted high-light
data for issues that hurt playback and evaluation, such as out-of-range times,
legacy type names, sentence-like interaction labels, and synthetic sources.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_HIGHLIGHT_DIR = ROOT / "data" / "highlights"
DEFAULT_REPORT = ROOT / "data" / "generated" / "review" / "highlight_quality_audit.md"

INTERACTION_MAP = {
    "家族冲突": "燃",
    "护短撑腰": "护主角",
    "身份反转": "炸裂",
    "年龄反差梗": "离谱",
    "打脸爽点": "爽",
    "反杀逆袭": "爽",
    "高能冲突": "燃",
    "反派压迫": "屏息",
    "搞笑包袱": "笑",
    "离谱吐槽": "离谱",
    "颜值名场面": "封神",
    "CP磕糖": "磕",
    "泪点破防": "破防",
    "治愈和解": "治愈",
    "剧情悬念": "炸裂",
    "上头追更": "上头",
    "角色高光": "燃",
    "名台词": "封神",
}
TYPE_ALIASES = {
    "冲突": "高能冲突",
    "悬念": "剧情悬念",
    "搞笑": "搞笑包袱",
    "爽点": "打脸爽点",
    "打脸": "打脸爽点",
    "反杀": "反杀逆袭",
    "反转": "身份反转",
    "名场面": "角色高光",
    "虐心": "泪点破防",
    "甜蜜": "CP磕糖",
    "高甜": "CP磕糖",
    "磕糖": "CP磕糖",
    "破防": "泪点破防",
    "紧张": "反派压迫",
}
INTERACTION_CHOICES = set(INTERACTION_MAP.values())
SYNTHETIC_SOURCES = {"ambient", "narrative_gen"}


def load_payload(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def source_of(item: dict[str, Any]) -> str:
    raw = item.get("raw") if isinstance(item.get("raw"), dict) else {}
    return str(item.get("source") or raw.get("source") or "unspecified")


def normalize_type(value: object) -> str:
    text = str(value or "角色高光").strip()
    return TYPE_ALIASES.get(text, text)


def normalize_interaction(value: object, htype: str) -> str:
    text = str(value or "").strip()
    if text in INTERACTION_CHOICES:
        return text
    return INTERACTION_MAP.get(htype, "爽")


def round_time(value: float, *, duration: float = 0.0) -> float:
    if duration > 0 and value >= duration:
        return math.floor(duration * 100) / 100
    return round(value, 2)


def normalize_item(item: dict[str, Any], *, duration: float) -> dict[str, Any] | None:
    try:
        ts_start = max(0.0, float(item.get("ts_start", 0.0)))
        ts_end = max(0.0, float(item.get("ts_end", 0.0)))
    except (TypeError, ValueError):
        return None
    if duration > 0:
        if ts_start >= duration:
            return None
        ts_end = min(ts_end, duration)
    if ts_end <= ts_start:
        return None
    htype = normalize_type(item.get("type"))
    interaction = normalize_interaction(item.get("interaction"), htype)
    raw = item.get("raw") if isinstance(item.get("raw"), dict) else {}
    raw = dict(raw)
    model_interaction = item.get("interaction")
    if model_interaction and str(model_interaction).strip() != interaction:
        raw["model_interaction"] = str(model_interaction).strip()
    out = dict(item)
    out.update(
        {
            "ts_start": round(ts_start, 2),
            "ts_end": round_time(ts_end, duration=duration),
            "type": htype,
            "interaction": interaction,
            "intensity": round(
                max(0.0, min(1.0, float(item.get("intensity", 0.6)))),
                3,
            ),
            "description": str(item.get("description") or "")[:80],
        }
    )
    if raw:
        out["raw"] = raw
    return out


def audit_file(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], list[str]]:
    payload = load_payload(path)
    duration = float(payload.get("duration") or 0.0)
    highlights = payload.get("highlights") or []
    issues: list[str] = []
    normalized: list[dict[str, Any]] = []
    previous_end = -1.0
    for index, item in enumerate(highlights):
        if not isinstance(item, dict):
            issues.append(f"{index}: item is not an object")
            continue
        src = source_of(item)
        if src in SYNTHETIC_SOURCES:
            issues.append(f"{index}: synthetic_source={src}")
        htype = str(item.get("type") or "")
        if htype in TYPE_ALIASES:
            issues.append(f"{index}: legacy_type={htype}->{TYPE_ALIASES[htype]}")
        interaction = str(item.get("interaction") or "")
        if interaction and interaction not in INTERACTION_CHOICES:
            issues.append(f"{index}: invalid_interaction={interaction[:24]}")
        try:
            ts_start = float(item.get("ts_start", 0.0))
            ts_end = float(item.get("ts_end", 0.0))
        except (TypeError, ValueError):
            issues.append(f"{index}: invalid_time")
            continue
        if ts_end <= ts_start:
            issues.append(f"{index}: invalid_range={ts_start}-{ts_end}")
        if duration > 0 and ts_start >= duration:
            issues.append(f"{index}: start_after_duration={ts_start}>{duration}")
        if duration > 0 and ts_end > duration:
            issues.append(f"{index}: end_after_duration={ts_end}>{duration}")
        if previous_end >= 0 and ts_start < previous_end:
            issues.append(f"{index}: overlap_previous={ts_start}<prev_end:{previous_end}")
        previous_end = max(previous_end, ts_end)
        clean = normalize_item(item, duration=duration)
        if clean is not None:
            normalized.append(clean)
    normalized.sort(key=lambda item: (item["ts_start"], item["ts_end"]))
    return payload, normalized, issues


def build_report(rows: list[dict[str, Any]]) -> str:
    total_files = len(rows)
    total_highlights = sum(row["count"] for row in rows)
    source_counter: Counter[str] = Counter()
    type_counter: Counter[str] = Counter()
    issue_counter: Counter[str] = Counter()
    prefix_counts: dict[str, list[int]] = defaultdict(list)
    for row in rows:
        source_counter.update(row["sources"])
        type_counter.update(row["types"])
        prefix_counts[row["episode_id"].split("_")[0]].append(row["count"])
        for issue in row["issues"]:
            issue_counter[issue.split("=", 1)[0].split(":", 1)[-1].strip()] += 1

    lines = [
        "# 高光识别结果质量诊断报告",
        "",
        "## 总览",
        "",
        f"- 文件数：{total_files}",
        f"- 高光总数：{total_highlights}",
        f"- 平均每集高光数：{round(total_highlights / total_files, 2) if total_files else 0}",
        "",
        "## 来源分布",
        "",
    ]
    for key, value in source_counter.most_common():
        lines.append(f"- {key}: {value}")
    lines.extend(["", "## 类型分布 Top 20", ""])
    for key, value in type_counter.most_common(20):
        lines.append(f"- {key}: {value}")
    lines.extend(["", "## 问题分布", ""])
    if issue_counter:
        for key, value in issue_counter.most_common():
            lines.append(f"- {key}: {value}")
    else:
        lines.append("- 未发现结构性问题")
    lines.extend(["", "## 剧集组覆盖", ""])
    for prefix, counts in sorted(prefix_counts.items()):
        lines.append(
            f"- {prefix}: {len(counts)} 集，平均 {round(sum(counts) / len(counts), 2)} 条，"
            f"范围 {min(counts)}-{max(counts)}"
        )
    lines.extend(["", "## 问题样例", ""])
    examples = []
    for row in rows:
        for issue in row["issues"][:5]:
            examples.append(f"- {row['episode_id']}: {issue}")
        if len(examples) >= 80:
            break
    lines.extend(examples or ["- 无"])
    lines.extend(
        [
            "",
            "## 建议",
            "",
            "- 导入数据库前统一裁剪时间边界，避免高光越过视频时长。",
            "- 将旧类型归一到短剧细分类，如“冲突”归为“高能冲突”。",
            "- 将模型生成的长句 interaction 保存到 raw.model_interaction，前端只下发短标签。",
            "- 答辩评测时区分 doubao_multimodal、rich_danmaku_peak、ambient、narrative_gen 来源。",
            "- 用 gold labels 评测真实识别来源，不把 ambient 节拍混入准确率统计。",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--highlight-dir", type=Path, default=DEFAULT_HIGHLIGHT_DIR)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--fix", action="store_true", help="rewrite highlight JSON with normalized items")
    args = parser.parse_args()

    rows: list[dict[str, Any]] = []
    for path in sorted(args.highlight_dir.glob("*.json")):
        payload, normalized, issues = audit_file(path)
        if args.fix:
            payload["highlights"] = normalized
            path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        sources = Counter(source_of(item) for item in normalized)
        types = Counter(str(item.get("type") or "") for item in normalized)
        rows.append(
            {
                "episode_id": path.stem,
                "count": len(normalized),
                "sources": sources,
                "types": types,
                "issues": issues,
            }
        )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(build_report(rows), encoding="utf-8")
    issue_count = sum(len(row["issues"]) for row in rows)
    print(f"audited {len(rows)} files, issues={issue_count}, report={args.report}")
    if args.fix:
        print("normalized highlight files in-place")


if __name__ == "__main__":
    main()
