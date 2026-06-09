# AI Pipeline

离线流水线，把一集 mp4 转成 `highlights.json`（含时间戳、剧情类型、互动标签和 AI 证据），再由后端导入到 `Highlight` 表，通过 `/api/highlights/{episode_id}` 下发给 Flutter 播放器。

## 目录分工

- `run_pipeline.py`：单集/批量入口，串起抽帧、ASR、候选筛选和 Doubao 识别。
- `extract_frames.py`：按镜头和固定间隔抽代表帧。
- `whisper_asr.py`：提取带时间戳字幕，给 Doubao 提供剧情上下文。
- `audio_highlight.py`：检测音频能量峰，召回争吵、爆点、音乐起势等候选窗口。
- `scene_detect.py`：检测镜头切点，召回转场、特写、节奏突变等候选窗口。
- `highlight_detector.py`：把“代表帧 + 同窗口字幕”送入 Doubao 多模态，输出结构化高光 JSON。
- `../data/highlights/`：每集产物目录，例如 `sbtnn_001.json`。

## 识别策略

1. **候选召回**：从镜头切换、音频峰值、固定时间窗召回可能高光，避免整集逐秒请求模型。
2. **剧情理解**：Doubao 同时看关键帧和字幕，判断当前窗口是不是身份揭露、护短撑腰、打脸爽点、反派压迫、泪点破防、剧情悬念等剧情节点。
3. **互动映射**：每个高光输出 `type`、`interaction`、`intensity`、`description`，并把 `narrative_role`、`trigger`、`evidence` 写进 `raw`，方便后端追溯和前端做不同互动效果。
4. **后处理**：合并相邻同类高光，过滤低置信度窗口，并保留类型多样性，避免整集全是同一种“爽点”。

## 三步走

1. **抽帧** — `extract_frames.py`：用 PySceneDetect 切场景，每个场景取代表帧；同时按固定间隔补一组 fallback 帧。
2. **字幕** — `whisper_asr.py`：用 Whisper 提取带时间戳的字幕（Mac M 系列自动 MPS 加速）。
3. **高光识别** — `highlight_detector.py`：将“帧 + 同窗口字幕”打包送入 Doubao 多模态，要求 JSON 输出。

## 单集运行

```bash
cd ai_pipeline
pip install -r requirements.txt   # 首次
cp .env.example .env              # 填 Doubao Key

python run_pipeline.py \
  --video ../../beipaixunbao/第63集.mp4 \
  --episode-id ep_063 \
  --out ../data/highlights/ep_063.json
```

## 批量

```bash
python run_pipeline.py --batch ../../beipaixunbao --out-dir ../data/highlights
```

## 产出 schema

```json
{
  "episode_id": "ep_063",
  "duration": 312.4,
  "highlights": [
    {
      "ts_start": 125.3,
      "ts_end": 132.8,
      "type": "身份反转",
      "interaction": "震惊",
      "intensity": 0.92,
      "description": "男主揭露真相，女配当场崩溃",
      "raw": {
        "source": "doubao_multimodal",
        "narrative_role": "真相揭露",
        "trigger": "角色身份被点破",
        "evidence": "台词提到真正身份"
      }
    }
  ]
}
```
