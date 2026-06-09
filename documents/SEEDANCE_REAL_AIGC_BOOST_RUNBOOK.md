# Seedance 真实加速包生成接入说明

更新时间：2026-06-04

## 当前结论

加速包链路已经切到真实 Seedance/即梦视频生成模式：

- `AIGC_VIDEO_PROVIDER=seedance`
- `AIGC_VIDEO_REAL_ENABLED=true`
- `AIGC_VIDEO_FALLBACK_TO_ASSETS=false`
- 真实任务接口：`POST https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks`
- 请求体使用官方 `model + content[]` 结构，生成完成后轮询 `GET .../tasks/{id}`，读取 `content.video_url` 并下载到本地 `/generated/aigc/*.mp4`

当前缺口是 Seedance 专用自定义 Endpoint ID。火山方舟返回：

```text
Accessing the model via Model ID is not allowed for your account. Please use a custom endpoint ID instead.
```

所以不能直接把 `doubao-seedance-1-0-pro-fast-251015` 当作 `model` 调用，必须在控制台创建/复制 `ep-...` 接入点。

## 控制台需要做什么

1. 进入火山方舟控制台。
2. 左侧进入 `在线推理` 或打开：
   `https://console.volcengine.com/ark/region:ark+cn-beijing/endpoint?current=1&pagesize=10`
3. 点击创建接入点。
4. 模型选择已开通的 `Doubao-Seedance-1.0-pro-fast`。
5. 创建后复制接入点 ID，格式通常为 `ep-xxxxxxxx...`。
6. 写入 `backend/.env`：

```bash
AIGC_VIDEO_ENDPOINT_ID=ep-你的Seedance接入点
```

## 真实预生成命令

```bash
backend/.venv/bin/python3 scripts/pregen_aigc_boosts.py \
  --episode-id ep_063 \
  --trigger-ts 56 \
  --resume-at 61 \
  --title 加速包 \
  --prompt '竖屏短剧加速包插片，雨夜救援飞车，火箭加速HUD，第一视角疾速推进，城市灯光掠过，保持当前短剧人物关系和紧张节奏，不出现无关人物，不跳到其他剧集，电影感高能，5秒，9:16，播完自然回到正片。' \
  --style-code short_drama_boost_seedance \
  --real-provider \
  --no-fallback \
  --force-new \
  --endpoint-id ep-你的Seedance接入点 \
  --timeout-seconds 600
```

成功后脚本会：

1. 创建 `aigc_video_jobs`。
2. 提交 Seedance 异步任务。
3. 轮询到 `ready`。
4. 下载临时 `video_url` 到 `data/generated/aigc/*.mp4`。
5. 通过质量闸门后发布 `aigc_boost_points`。

## 首尾帧说明

本地默认 `PUBLIC_BASE_URL=http://127.0.0.1:8000`，云端无法访问这个地址，所以当前会自动走真实文生视频。要升级成首尾帧图生视频，需要配置：

```bash
AIGC_MEDIA_PUBLIC_BASE_URL=https://你的公网域名
```

这个公网域名需要能访问：

- `/frames/{episode_id}/xxx.jpg`
- `/generated/aigc/*.mp4`

长期建议用 TOS/OSS 临时 URL；本地演示可用 cloudflared/ngrok 暴露。

## 验收

```bash
curl -s http://127.0.0.1:8000/api/aigc-video/boost-points/ep_063 | python3 -m json.tool
```

返回中应看到：

- `provider=seedance`
- `output_video_url=/generated/aigc/*.mp4`
- `status=published`

播放器进到 `trigger_ts` 附近会出现加速包图层，点击后播放生成视频，播放完成后使用
`Media(start: resume_at)` 重新打开正片，并补一次 seek 校验，避免恢复到 0 秒。

生成时长与正片续播点已经解耦：

- `AIGC_INSERT_DURATION_SECONDS=12`：Seedance 生成视频时长。
- `AIGC_RESUME_OFFSET_SECONDS=5`：正片从触发点后 5 秒继续。
- `AIGC_VIDEO_PROVIDER_MAX_DURATION_SECONDS=12`：当前 Seedance 1.0 pro fast 接入点上限。

例如触发点为 56 秒，生成 12 秒插片，插片结束后仍从正片 61 秒继续。若切换到
Seedance 1.5 pro 或 2.0 接入点，可将 provider 上限改为 15 秒。
