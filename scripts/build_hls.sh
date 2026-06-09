#!/usr/bin/env bash
# 批量把 mp4 源转码为多码率 HLS（540p / 720p / 1080p）+ master.m3u8
#
# 用法：
#   scripts/build_hls.sh \
#     --src /Users/daiqixu/Desktop/duanjujifa/beipaixunbao \
#     --pattern "第*集.mp4" \
#     --id-prefix ep_ \
#     --offset 62                  # 第63集.mp4 -> ep_001
#     --only 6,7,8                 # 只处理指定集号或 episode_id
#     --force                      # 覆盖已有 HLS 产物
#
# 输出目录：short-drama-interaction/data/hls/<ep_id>/{540p,720p,1080p,master.m3u8}
#
# 已存在 master.m3u8 的集默认跳过，可用 --force 重建。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HLS_ROOT="$ROOT/data/hls"

SRC=""
PATTERN="第*集.mp4"
ID_PREFIX="ep_"
OFFSET=0       # 文件「第N集」中 N - OFFSET = 实际序号；OFFSET=62 表示 第63集->001
PAD=3          # 序号补零位数
ONLY=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --pattern) PATTERN="$2"; shift 2 ;;
    --id-prefix) ID_PREFIX="$2"; shift 2 ;;
    --offset) OFFSET="$2"; shift 2 ;;
    --pad) PAD="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SRC" ]]; then
  echo "缺少 --src 参数" >&2; exit 1
fi

command -v ffmpeg >/dev/null || { echo "未找到 ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "未找到 ffprobe" >&2; exit 1; }

mkdir -p "$HLS_ROOT"

in_only() {
  [[ -z "$ONLY" ]] && return 0
  local item
  IFS=',' read -ra items <<< "$ONLY"
  for item in "${items[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -z "$item" ]] && continue
    if [[ "$item" == "$ep_id" ]]; then
      return 0
    fi
    if [[ "$item" =~ ^[0-9]+$ ]] && (( 10#$item == idx )); then
      return 0
    fi
  done
  return 1
}

calc_width() {
  local target_height="$1"
  local width=$(( (src_w * target_height + src_h / 2) / src_h ))
  if (( width % 2 )); then
    width=$((width + 1))
  fi
  echo "$width"
}

shopt -s nullglob
for mp4 in "$SRC"/$PATTERN; do
  [[ -e "$mp4" ]] || continue
  base=$(basename "$mp4")
  # 抽取数字
  num=$(echo "$base" | grep -oE '[0-9]+' | head -1)
  [[ -z "$num" ]] && { echo "[skip] 无法解析序号: $base"; continue; }
  idx=$((num - OFFSET))
  printf -v padded "%0${PAD}d" "$idx"
  ep_id="${ID_PREFIX}${padded}"
  if ! in_only; then
    continue
  fi
  out_dir="$HLS_ROOT/$ep_id"
  master="$out_dir/master.m3u8"

  if [[ -f "$master" && "$FORCE" -eq 0 ]]; then
    echo "[skip] $ep_id 已存在"
    continue
  fi
  if [[ "$FORCE" -eq 1 ]]; then
    rm -rf "$out_dir"
  fi

  echo "[hls ] $base -> $ep_id"
  mkdir -p "$out_dir/540p" "$out_dir/720p" "$out_dir/1080p"

  IFS=',' read -r src_w src_h < <(
    ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0 "$mp4"
  )
  w540=$(calc_width 540)
  w720=$(calc_width 720)
  w1080=$(calc_width 1080)

  # 使用 filter_complex split 单次读取，三路同时转码
  ffmpeg -y -hide_banner -loglevel error -i "$mp4" \
    -filter_complex "[0:v]split=3[v1][v2][v3]; \
      [v1]scale=-2:540:flags=lanczos[out540]; \
      [v2]scale=-2:720:flags=lanczos[out720]; \
      [v3]scale=-2:1080:flags=lanczos[out1080]" \
    \
    -map "[out540]" -map "0:a?" \
      -c:v libx264 -profile:v main -preset medium -crf 22 -b:v 1400k -maxrate 1600k -bufsize 2800k \
      -pix_fmt yuv420p -g 96 -keyint_min 96 -sc_threshold 0 \
      -c:a aac -b:a 96k -ac 2 \
      -hls_time 6 -hls_playlist_type vod \
      -hls_segment_filename "$out_dir/540p/seg_%03d.ts" \
      "$out_dir/540p/index.m3u8" \
    \
    -map "[out720]" -map "0:a?" \
      -c:v libx264 -profile:v main -preset medium -crf 20 -b:v 2800k -maxrate 3200k -bufsize 5600k \
      -pix_fmt yuv420p -g 96 -keyint_min 96 -sc_threshold 0 \
      -c:a aac -b:a 128k -ac 2 \
      -hls_time 6 -hls_playlist_type vod \
      -hls_segment_filename "$out_dir/720p/seg_%03d.ts" \
      "$out_dir/720p/index.m3u8" \
    \
    -map "[out1080]" -map "0:a?" \
      -c:v libx264 -profile:v high -preset medium -crf 18 -b:v 5000k -maxrate 5800k -bufsize 10000k \
      -pix_fmt yuv420p -g 96 -keyint_min 96 -sc_threshold 0 \
      -c:a aac -b:a 128k -ac 2 \
      -hls_time 6 -hls_playlist_type vod \
      -hls_segment_filename "$out_dir/1080p/seg_%03d.ts" \
      "$out_dir/1080p/index.m3u8"

  cache_buster=$(date +%s)

  cat > "$master" <<EOF
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=5800000,RESOLUTION=${w1080}x1080,CODECS="avc1.640028,mp4a.40.2"
1080p/index.m3u8?v=${cache_buster}
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=${w720}x720,CODECS="avc1.4d401f,mp4a.40.2"
720p/index.m3u8?v=${cache_buster}
#EXT-X-STREAM-INF:BANDWIDTH=1600000,RESOLUTION=${w540}x540,CODECS="avc1.4d401e,mp4a.40.2"
540p/index.m3u8?v=${cache_buster}
EOF

  echo "[done] $ep_id"
done

echo "全部完成。"
