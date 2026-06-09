#!/usr/bin/env python3
"""叙事高光生成器 —— 为「没有弹幕来源」的剧集批量生成贴合题材的剧情高光节拍。

适用场景：
- 圈选弹幕 CSV 只覆盖每部剧的前 5 集，第 6 集起没有弹幕，无法用弹幕峰值法产出高光；
- 但视频本身存在（可 ffprobe 出真实时长），需要让这些集也具备「高光 → 情绪特效 → 互动」的体验。

策略：
- 读取源视频真实时长（ffprobe），按 ~SPACING 秒铺设节拍，jitter 让节奏自然；
- 类型在题材专属的「剧情高光分类」里加权轮换，且避免相邻重复，保证多样；
- 每个类型配套题材贴合的文案池 + 互动标签 + 情绪强度，强度带轻微抖动；
- 产出与 AI Pipeline 完全一致的 schema（data/highlights/<ep>.json），
  可直接被 POST /api/highlights/import/<ep> 导入，也可继续用 densify 增密。

用法：
    python3 scripts/gen_narrative_highlights.py --drama shibasuitainainai \
        --prefix sbtnn_ --start 6 --end 26
    python3 scripts/gen_narrative_highlights.py --drama tianxiadyi \
        --prefix txy_ --start 6 --end 24 --force
"""
from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data" / "highlights"
JUBEN_DIR = ROOT.parent / "juben"

SPACING = 26.0          # 节拍目标间隔（秒）
JITTER = 6.0            # 间隔抖动
WINDOW_MIN = 7.0
WINDOW_MAX = 12.0
EDGE = 6.0             # 片头/片尾留白

INTERACTION_MAP = {
    "身份反转": "炸裂",
    "护短撑腰": "燃",
    "打脸爽点": "爽",
    "反杀逆袭": "爽",
    "年龄反差梗": "离谱",
    "家族冲突": "屏息",
    "反派压迫": "屏息",
    "剧情悬念": "炸裂",
    "泪点破防": "破防",
    "治愈和解": "治愈",
    "搞笑包袱": "笑",
    "CP磕糖": "磕",
    "颜值名场面": "封神",
    "高能冲突": "燃",
}

# 题材专属：类型权重 + 文案池（贴合各剧基调）
DRAMA_PACKS: dict[str, dict] = {
    "shibasuitainainai": {
        "weights": {
            "年龄反差梗": 1.6,
            "护短撑腰": 1.5,
            "搞笑包袱": 1.35,
            "身份反转": 1.3,
            "打脸爽点": 1.25,
            "家族冲突": 1.15,
            "泪点破防": 1.05,
            "治愈和解": 1.0,
            "剧情悬念": 0.95,
            "CP磕糖": 0.8,
            "颜值名场面": 0.78,
            "反派压迫": 0.9,
        },
        "desc": {
            "年龄反差梗": ["十八岁太奶奶辈分碾压全场", "嫩脸祖奶奶亮明身份惊呆众人",
                          "小姑娘一开口竟是老祖宗", "扮嫩太奶奶辈分压死人"],
            "护短撑腰": ["太奶奶当众为孙辈撑腰", "谁敢欺负我家人当场翻脸",
                        "霸气护短一句话镇住全场", "祖奶奶亲自下场护犊子"],
            "搞笑包袱": ["一句吐槽逗笑全场", "沙雕操作笑翻众人",
                        "反差萌瞬间笑点拉满", "神补刀引爆笑点"],
            "身份反转": ["神秘身份当场揭穿", "真实辈分震惊四座",
                        "隐藏大佬身份曝光", "反转揭底全场哗然"],
            "打脸爽点": ["势利眼被当场打脸", "看不起人反被狠狠打脸",
                        "嘲讽者自取其辱", "啪啪打脸大快人心"],
            "家族冲突": ["家产之争摆上台面", "长辈逼迫针锋相对",
                        "家族矛盾一触即发", "饭桌摊牌火药味十足"],
            "泪点破防": ["隐忍往事戳中泪点", "一家团圆瞬间破防",
                        "委屈说出口让人心疼", "回忆涌上心头泪目"],
            "治愈和解": ["误会解开重归于好", "家人围坐温情时刻",
                        "和解拥抱治愈满分", "矛盾化解暖意流淌"],
            "剧情悬念": ["关键线索抛出留悬念", "一句话埋下伏笔",
                        "真相呼之欲出", "悬念拉满吊足胃口"],
            "CP磕糖": ["两人互动甜度飙升", "不经意撒糖磕到了",
                      "暧昧氛围拉满", "细节藏糖甜到齁"],
            "颜值名场面": ["主角高光颜值封神", "回眸一笑惊艳全场",
                          "气场全开颜值在线", "名场面颜值暴击"],
            "反派压迫": ["反派步步紧逼气氛压抑", "恶意算计逼上门来",
                        "压迫感拉满令人屏息", "阴谋逼近危机四伏"],
        },
    },
    "tianxiadyi": {
        "weights": {
            "打脸爽点": 1.5,
            "高能冲突": 1.35,
            "身份反转": 1.3,
            "护短撑腰": 1.2,
            "反杀逆袭": 1.2,
            "剧情悬念": 1.1,
            "颜值名场面": 1.0,
            "搞笑包袱": 0.95,
            "反派压迫": 0.9,
            "泪点破防": 0.85,
        },
        "desc": {
            "打脸爽点": ["纨绔真身当众打脸", "看人下菜碟被狠狠打脸",
                        "嘲讽者瞬间被打脸", "实力碾压啪啪打脸"],
            "高能冲突": ["当众对峙剑拔弩张", "正面硬刚气势全开",
                        "针锋相对火花四溅", "强强对撞燃到炸裂"],
            "身份反转": ["隐藏身份当场曝光", "真实来头震惊众人",
                        "镇北侯名号一出全场错愕", "反转揭底气场拉满"],
            "护短撑腰": ["为自己人强势出头", "霸气护短镇住对手",
                        "谁动我的人就别想好过", "撑腰到底气场全开"],
            "反杀逆袭": ["绝境反杀逆风翻盘", "被逼到底强势反击",
                        "一招制胜逆袭翻盘", "反客为主逆转战局"],
            "剧情悬念": ["抛出隐患埋下伏笔", "一句话引出悬念",
                        "暗流涌动真相成谜", "悬念拉满吊足胃口"],
            "颜值名场面": ["主角气场颜值封神", "睥睨全场气场拉满",
                          "回眸一笑惊艳众人", "名场面气场暴击"],
            "搞笑包袱": ["夸张神态笑点拉满", "一句话逗笑全场",
                        "沙雕反差笑翻众人", "神补刀引爆笑点"],
            "反派压迫": ["反派步步紧逼气氛压抑", "权势压人危机逼近",
                        "压迫感拉满令人屏息", "阴谋逼近暗藏杀机"],
            "泪点破防": ["隐忍心事戳中泪点", "旧事重提让人破防",
                        "苦衷说出口令人心疼", "情绪涌上泪目时刻"],
        },
    },
}

# 通用兜底文案
GENERIC_DESC = {
    "搞笑包袱": "笑点拉满", "剧情悬念": "悬念升起", "护短撑腰": "霸气护短",
    "打脸爽点": "当众打脸", "身份反转": "身份反转", "家族冲突": "矛盾激化",
    "泪点破防": "情绪破防", "治愈和解": "温情和解", "年龄反差梗": "反差名场面",
    "反派压迫": "压迫拉满", "CP磕糖": "撒糖时刻", "颜值名场面": "颜值封神",
    "反杀逆袭": "逆袭反杀", "高能冲突": "高能对峙",
}


def probe_duration(path: Path) -> float:
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
            check=True, capture_output=True, text=True,
        )
        return max(float(out.stdout.strip()), 0.0)
    except Exception:
        return 0.0


def weighted_pick(rng: random.Random, weights: dict[str, float], avoid: str | None) -> str:
    items = [(k, v) for k, v in weights.items() if k != avoid] or list(weights.items())
    total = sum(v for _, v in items)
    r = rng.uniform(0, total)
    acc = 0.0
    for k, v in items:
        acc += v
        if r <= acc:
            return k
    return items[-1][0]


def generate(drama: str, ep_id: str, duration: float, seed: int) -> dict:
    pack = DRAMA_PACKS.get(drama, DRAMA_PACKS["shibasuitainainai"])
    weights = pack["weights"]
    desc_pool = pack["desc"]
    rng = random.Random(f"{ep_id}:{seed}")

    highlights: list[dict] = []
    ts = EDGE + rng.uniform(2.0, 8.0)
    last_type: str | None = None
    used_desc: set[str] = set()

    while ts < duration - EDGE:
        kind = weighted_pick(rng, weights, last_type)
        last_type = kind
        window = rng.uniform(WINDOW_MIN, WINDOW_MAX)
        ts_end = min(ts + window, duration - 1.0)

        pool = [d for d in desc_pool.get(kind, []) if d not in used_desc] \
            or desc_pool.get(kind, [GENERIC_DESC.get(kind, "高光时刻")])
        description = rng.choice(pool)
        used_desc.add(description)

        # 强度：权重越高基础越高，再加抖动
        base = 0.55 + min(weights.get(kind, 1.0), 1.6) / 1.6 * 0.28
        intensity = round(min(max(base + rng.uniform(-0.06, 0.08), 0.55), 0.95), 3)

        highlights.append({
            "ts_start": round(ts, 2),
            "ts_end": round(ts_end, 2),
            "type": kind,
            "interaction": INTERACTION_MAP.get(kind, "爽"),
            "intensity": intensity,
            "description": description,
            "source": "narrative_gen",
            "raw": {
                "source": "narrative_gen",
                "drama": drama,
                "note": "无弹幕集：按视频时长生成的题材化剧情高光节拍",
            },
        })
        ts += SPACING + rng.uniform(-JITTER, JITTER)

    return {"episode_id": ep_id, "duration": round(duration, 3), "highlights": highlights}


def main() -> None:
    ap = argparse.ArgumentParser(description="为无弹幕剧集生成题材化叙事高光")
    ap.add_argument("--drama", required=True, help="剧集目录名 (juben/<drama>)")
    ap.add_argument("--prefix", required=True, help="集 id 前缀，如 sbtnn_ / txy_")
    ap.add_argument("--start", type=int, required=True)
    ap.add_argument("--end", type=int, required=True)
    ap.add_argument("--pad", type=int, default=3)
    ap.add_argument("--seed", type=int, default=20260514)
    ap.add_argument("--force", action="store_true", help="覆盖已存在的高光 JSON")
    args = ap.parse_args()

    video_root = JUBEN_DIR / args.drama
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    for no in range(args.start, args.end + 1):
        ep_id = f"{args.prefix}{no:0{args.pad}d}"
        out_path = DATA_DIR / f"{ep_id}.json"
        if out_path.exists() and not args.force:
            print(f"{ep_id}: skip (exists)")
            continue

        video = video_root / f"第{no}集.mp4"
        if not video.exists():
            print(f"{ep_id}: skip (no video {video.name})")
            continue
        duration = probe_duration(video)
        if duration <= 0:
            print(f"{ep_id}: skip (probe failed)")
            continue

        payload = generate(args.drama, ep_id, duration, args.seed)
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{ep_id}: dur={round(duration,1)}s highlights={len(payload['highlights'])}")


if __name__ == "__main__":
    main()
