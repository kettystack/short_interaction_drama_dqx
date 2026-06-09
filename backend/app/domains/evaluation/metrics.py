from __future__ import annotations

from dataclasses import dataclass

from ...models import Highlight, HighlightGoldLabel


@dataclass
class MatchItem:
    gold_label_id: int | None
    pred_highlight_id: int | None
    match_type: str
    iou: float = 0.0
    type_match: bool = False
    note: str = ""


@dataclass
class MatchResult:
    items: list[MatchItem]
    precision: float
    recall: float
    f1: float
    type_accuracy: float
    tp: int
    fp: int
    fn: int


def time_iou(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    inter = max(0.0, min(a_end, b_end) - max(a_start, b_start))
    union = max(a_end, b_end) - min(a_start, b_start)
    if union <= 0:
        return 0.0
    return inter / union


def match_highlights(
    gold: list[HighlightGoldLabel],
    pred: list[Highlight],
    *,
    iou_threshold: float = 0.3,
) -> MatchResult:
    candidates: list[tuple[float, HighlightGoldLabel, Highlight]] = []
    for g in gold:
        for p in pred:
            score = time_iou(g.ts_start, g.ts_end, p.ts_start, p.ts_end)
            if score >= iou_threshold:
                candidates.append((score, g, p))
    candidates.sort(key=lambda item: item[0], reverse=True)

    used_gold: set[int] = set()
    used_pred: set[int] = set()
    items: list[MatchItem] = []
    type_hits = 0

    for score, g, p in candidates:
        if g.id in used_gold or p.id in used_pred:
            continue
        used_gold.add(g.id)
        used_pred.add(p.id)
        type_match = g.type == p.type
        if type_match:
            type_hits += 1
        items.append(
            MatchItem(
                gold_label_id=g.id,
                pred_highlight_id=p.id,
                match_type="tp",
                iou=round(score, 4),
                type_match=type_match,
            )
        )

    for p in pred:
        if p.id not in used_pred:
            items.append(
                MatchItem(
                    gold_label_id=None,
                    pred_highlight_id=p.id,
                    match_type="fp",
                    note="predicted highlight did not match any gold label",
                )
            )

    for g in gold:
        if g.id not in used_gold:
            items.append(
                MatchItem(
                    gold_label_id=g.id,
                    pred_highlight_id=None,
                    match_type="fn",
                    note="gold label was missed by pipeline",
                )
            )

    tp = len(used_gold)
    fp = len(pred) - len(used_pred)
    fn = len(gold) - len(used_gold)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    type_accuracy = type_hits / tp if tp else 0.0
    return MatchResult(
        items=items,
        precision=round(precision, 4),
        recall=round(recall, 4),
        f1=round(f1, 4),
        type_accuracy=round(type_accuracy, 4),
        tp=tp,
        fp=fp,
        fn=fn,
    )

