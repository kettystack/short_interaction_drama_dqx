from __future__ import annotations

import argparse
import asyncio
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

from sqlalchemy import delete, select

from app.config import settings
from app.database import SessionLocal, init_db
from app.models import DanmakuItem, Episode, Highlight

BUCKET_SECONDS = 8.0
MAX_HIGHLIGHTS_PER_EPISODE = 10
MAX_HIGHLIGHTS_PER_TYPE = 2
MIN_BUCKET_COUNT = 3
MIN_GAP_SECONDS = 12.0

TYPE_KEYWORDS: dict[str, list[str]] = {
    "家族冲突": ["家族", "一家", "亲戚", "父母", "爸爸", "妈妈", "爷爷", "奶奶", "儿子", "女儿", "家里", "族"],
    "护短撑腰": ["撑腰", "护", "护短", "帮", "靠山", "主角", "别怕", "爷", "太奶", "老祖", "英台"],
    "身份反转": ["身份", "原来", "竟然", "其实", "真相", "认出", "发现", "暴露", "反转", "转折"],
    "年龄反差梗": ["十八", "18", "太奶", "奶奶", "老", "年轻", "学生", "小孩", "岁", "年龄"],
    "打脸爽点": ["打脸", "脸疼", "啪啪", "报应", "解气", "爽", "舒服", "痛快", "活该"],
    "反杀逆袭": ["反杀", "逆袭", "翻盘", "反击", "杀回去", "赢", "拿下", "硬刚"],
    "高能冲突": ["杀", "打", "怒", "仇", "狠", "滚", "废", "威胁", "吵", "撕", "冲突"],
    "反派压迫": ["危险", "压迫", "窒息", "紧张", "害怕", "快跑", "坏", "恶", "欺负", "逼"],
    "搞笑包袱": ["笑", "哈哈", "鹅", "蚌", "乐", "搞笑", "笑死", "绷不住", "离谱"],
    "离谱吐槽": ["离谱", "绝了", "什么鬼", "这也", "笑不活", "魔幻", "无语", "夸张"],
    "颜值名场面": ["帅", "漂亮", "好看", "可爱", "颜值", "美", "绝", "封神", "名场面"],
    "CP磕糖": ["磕", "好配", "甜", "宠", "亲", "心动", "在一起", "cp", "CP"],
    "泪点破防": ["破防", "哭", "泪", "虐", "惨", "心疼", "可怜", "抱抱", "戳心"],
    "治愈和解": ["治愈", "温暖", "安心", "好暖", "和解", "原谅", "感动", "暖"],
    "剧情悬念": ["悬", "谜", "谁", "怎么", "为什么", "等会", "后面", "接下来", "秘密"],
    "上头追更": ["上头", "停不下", "继续", "别停", "追", "下一集", "好看", "还想看"],
}

INTERACTION_MAP = {
    "家族冲突": "燃",
    "护短撑腰": "护主角",
    "身份反转": "震惊",
    "年龄反差梗": "离谱",
    "打脸爽点": "爽",
    "反杀逆袭": "反杀",
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
}

TYPE_WEIGHTS = {
    "身份反转": 1.8,
    "护短撑腰": 1.65,
    "打脸爽点": 1.6,
    "反杀逆袭": 1.55,
    "剧情悬念": 1.5,
    "年龄反差梗": 1.45,
    "反派压迫": 1.4,
    "家族冲突": 1.25,
    "高能冲突": 1.2,
    "泪点破防": 1.05,
    "治愈和解": 1.0,
    "离谱吐槽": 0.9,
    "颜值名场面": 0.78,
    "CP磕糖": 0.74,
    "上头追更": 0.72,
    "搞笑包袱": 0.62,
}

BRACKET_RE = re.compile(r"\[[^\]]{1,8}\]")
NOISE_RE = re.compile(r"^(\d+刷|[nN]刷|[1-9]\d*$|[哈啊呀哦嗯]+|[\W_]+)$")


def score_texts(texts: list[str]) -> Counter[str]:
    scores: Counter[str] = Counter()
    joined = " ".join(texts)
    for highlight_type, keywords in TYPE_KEYWORDS.items():
        for keyword in keywords:
            matches = joined.count(keyword)
            if matches:
                scores[highlight_type] += matches
    return scores


def classify_texts(texts: list[str]) -> tuple[str, Counter[str]]:
    scores = score_texts(texts)
    if not scores:
        return "颜值名场面", scores
    highlight_type = max(
        scores,
        key=lambda item: (scores[item] * TYPE_WEIGHTS.get(item, 1.0), scores[item]),
    )
    return highlight_type, scores


def clean_comment(text: str) -> str:
    value = BRACKET_RE.sub("", text).strip()
    value = re.sub(r"\s+", " ", value)
    value = re.sub(r"(.)\1{5,}", r"\1\1\1", value)
    return value[:36]


def _matches_highlight_type(text: str, highlight_type: str) -> bool:
    keywords = TYPE_KEYWORDS.get(highlight_type, [])
    return any(keyword in text for keyword in keywords if len(keyword) >= 2)


def representative_comments(items: list[DanmakuItem], highlight_type: str) -> list[str]:
    ranked = sorted(
        items,
        key=lambda item: (item.like_count, len(clean_comment(item.text))),
        reverse=True,
    )
    type_matched = [item for item in ranked if _matches_highlight_type(item.text, highlight_type)]
    ranked = type_matched + [item for item in ranked if item not in type_matched]
    comments: list[str] = []
    seen: set[str] = set()
    for item in ranked:
        value = clean_comment(item.text)
        if len(value) < 2 or value in seen or NOISE_RE.match(value):
            continue
        seen.add(value)
        comments.append(value)
        if len(comments) >= 3:
            break
    return comments


def representative_words(texts: list[str]) -> list[str]:
    words: Counter[str] = Counter()
    for text in texts:
        compact = text.strip()
        if 2 <= len(compact) <= 12:
            words[compact] += 1
        for keyword_list in TYPE_KEYWORDS.values():
            for keyword in keyword_list:
                if keyword in text:
                    words[keyword] += 2
    return [word for word, _count in words.most_common(3)]


def describe_highlight(highlight_type: str, comments: list[str], words: list[str], count: int) -> str:
    if comments:
        evidence = comments[0]
    elif words:
        evidence = " / ".join(words)
    else:
        evidence = "观众集中互动"
    return f"{highlight_type}：{evidence}（{count}条弹幕共振）"


def choose_peaks(items: list[DanmakuItem]) -> list[dict]:
    buckets: dict[int, list[DanmakuItem]] = defaultdict(list)
    for item in items:
        bucket = int(item.ts_in_video // BUCKET_SECONDS)
        buckets[bucket].append(item)

    ranked = sorted(
        buckets.items(),
        key=lambda pair: (-len(pair[1]), pair[0]),
    )
    if not ranked:
        return []

    max_count = max(len(bucket_items) for _bucket, bucket_items in ranked)
    selected: list[dict] = []
    selected_times: list[float] = []
    selected_types: Counter[str] = Counter()

    for bucket, bucket_items in ranked:
        count = len(bucket_items)
        if count < MIN_BUCKET_COUNT:
            continue
        ts_start = bucket * BUCKET_SECONDS
        center = ts_start + BUCKET_SECONDS / 2
        if any(abs(center - existing) < MIN_GAP_SECONDS for existing in selected_times):
            continue
        texts = [item.text for item in bucket_items]
        highlight_type, scores = classify_texts(texts)
        if selected_types[highlight_type] >= MAX_HIGHLIGHTS_PER_TYPE and len(selected) >= 4:
            continue
        words = representative_words(texts)
        comments = representative_comments(bucket_items, highlight_type)
        intensity = min(0.98, 0.55 + (count / max_count) * 0.4)
        selected.append(
            {
                "ts_start": max(0.0, ts_start - 2.0),
                "ts_end": ts_start + BUCKET_SECONDS + 3.0,
                "type": highlight_type,
                "interaction": INTERACTION_MAP.get(highlight_type, "爽"),
                "intensity": round(intensity, 3),
                "description": describe_highlight(highlight_type, comments, words, count),
                "raw": {
                    "source": "rich_danmaku_peak",
                    "bucket": bucket,
                    "count": count,
                    "top_words": words,
                    "evidence_comments": comments,
                    "type_scores": dict(scores.most_common(6)),
                },
            }
        )
        selected_times.append(center)
        selected_types[highlight_type] += 1
        if len(selected) >= MAX_HIGHLIGHTS_PER_EPISODE:
            break

    return sorted(selected, key=lambda item: item["ts_start"])


async def seed(episode_ids: list[str]) -> None:
    await init_db()
    output_dir = Path(settings.data_root) / "highlights"
    output_dir.mkdir(parents=True, exist_ok=True)

    async with SessionLocal() as db:
        total = 0
        for episode_id in episode_ids:
            episode = await db.get(Episode, episode_id)
            if not episode:
                print(f"skip {episode_id}: episode missing")
                continue

            result = await db.execute(
                select(DanmakuItem)
                .where(DanmakuItem.episode_id == episode_id, DanmakuItem.status == "visible")
                .order_by(DanmakuItem.ts_in_video)
            )
            items = list(result.scalars().all())
            peaks = choose_peaks(items)

            await db.execute(delete(Highlight).where(Highlight.episode_id == episode_id))
            for peak in peaks:
                db.add(
                    Highlight(
                        episode_id=episode_id,
                        ts_start=float(peak["ts_start"]),
                        ts_end=float(peak["ts_end"]),
                        type=str(peak["type"]),
                        interaction=str(peak["interaction"]),
                        intensity=float(peak["intensity"]),
                        description=str(peak["description"]),
                        raw=peak.get("raw", {}),
                    )
                )
            await db.commit()

            output = {
                "episode_id": episode_id,
                "duration": episode.duration,
                "highlights": peaks,
            }
            (output_dir / f"{episode_id}.json").write_text(
                json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            total += len(peaks)
            print(f"{episode_id}: {len(peaks)} highlights from {len(items)} danmaku")
        print(f"imported {total} highlights")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate highlights from danmaku peaks.")
    parser.add_argument("episode_ids", nargs="*")
    parser.add_argument("--prefix", default="txy_")
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=5)
    args = parser.parse_args()

    episode_ids = (
        args.episode_ids
        if args.episode_ids
        else [f"{args.prefix}{episode_no:03d}" for episode_no in range(args.start, args.end + 1)]
    )
    asyncio.run(seed(episode_ids))


if __name__ == "__main__":
    main()
