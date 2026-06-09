#!/usr/bin/env bash
# 批量生成两部剧的高光 JSON。
#
# 默认对 beipaixunbao 第64~80 集（ep_064~ep_080）和 tianxiadyi 第6~24 集
# （txy_006~txy_024）调用 ai_pipeline/run_pipeline.py。已有 JSON 会被跳过。
#
# 用法：
#   scripts/build_highlights.sh           # 全部默认范围
#   scripts/build_highlights.sh --bpxb-only
#   scripts/build_highlights.sh --txy-only
#   ARK_API_KEY=xxx scripts/build_highlights.sh
#
# 依赖：python3、ffmpeg、whisper（除非传 --skip-asr）、Doubao Ark 接口（ARK_API_KEY）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"

BPXB_DIR="$REPO/beipaixunbao"
TXY_DIR="$REPO/tianxiadyi"
OUT_DIR="$ROOT/data/highlights"
WORK_DIR="$ROOT/data"

BPXB_ONLY=0
TXY_ONLY=0
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bpxb-only) BPXB_ONLY=1; shift ;;
    --txy-only)  TXY_ONLY=1; shift ;;
    --skip-asr|*) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

mkdir -p "$OUT_DIR"
cd "$ROOT/ai_pipeline"

run_batch() {
  local src="$1"; local prefix="$2"; local only="$3"
  if [[ ! -d "$src" ]]; then
    echo "[warn] 目录不存在: $src" >&2; return 0
  fi
  echo "[batch] prefix=$prefix src=$src only=${only:-all}"
  python3 run_pipeline.py \
    --batch "$src" \
    --prefix "$prefix" \
    --out-dir "$OUT_DIR" \
    --work-dir "$WORK_DIR" \
    ${only:+--only "$only"} \
    "${EXTRA_ARGS[@]}"
}

if [[ "$TXY_ONLY" -ne 1 ]]; then
  # 已完成 ep_063；其余按需补
  run_batch "$BPXB_DIR" "ep_" "64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80"
fi

if [[ "$BPXB_ONLY" -ne 1 ]]; then
  # 已完成 txy_001~txy_005；其余按需补
  run_batch "$TXY_DIR" "txy_" "6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24"
fi

echo "全部任务结束。生成的 JSON 位于: $OUT_DIR"
