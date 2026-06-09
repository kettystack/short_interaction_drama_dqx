# Short Drama Interaction · 短剧即时互动系统

基于短剧剧情的 AI 即时互动激发 — 全栈项目。

详细的本地启动方式见 `LOCAL_RUN_GUIDE.md`；答辩录屏脚本与本次增量说明见 `DELIVERY_DEMO_GUIDE.md`。

## 架构概览

```
short-drama-interaction/
├── flutter_app/     # Flutter 跨平台客户端（Android / iOS / macOS）
├── backend/         # FastAPI + SQLAlchemy + WebSocket
├── ai_pipeline/     # FFmpeg 抽帧 + Whisper 字幕 + Doubao 高光识别
├── data/            # 视频/帧/字幕/高光点 JSON
├── docker-compose.yml
└── scripts/
```

## 技术栈

| 层 | 选型 |
| - | - |
| 客户端 | Flutter 3 + Dart（Android / iOS / macOS 跨平台） |
| 后端 | FastAPI + SQLAlchemy + asyncpg + Redis + WebSocket |
| AI | Doubao-Seed-2.0-lite（多模态） + Whisper（本地） + FFmpeg + PySceneDetect |
| 基础设施 | PostgreSQL + Redis + Docker Compose |

## 快速开始（Mac）

### 0. 系统依赖
```bash
brew install ffmpeg python@3.11 node
```

### 1. 启动基础设施（Postgres + Redis）
```bash
docker compose up -d postgres redis
```

### 2. 后端
```bash
cd backend
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # 填入 DOUBAO API KEY
uvicorn app.main:app --reload --port 8000
```

### 3. Flutter 客户端
```bash
cd flutter_app
flutter pub get
# macOS 本地调试
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
# 构建 Android APK（真机替换 IP）
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

### 4. AI Pipeline（离线批量处理高光点）
```bash
cd ai_pipeline
pip install -r requirements.txt
python run_pipeline.py --video ../../beipaixunbao/第63集.mp4 --episode-id ep_063
```

## MVP 闭环

1. 用户访问短剧列表 → 选择剧集 → 进入播放页
2. 播放过程中前端轮询/订阅高光点 → 命中时间区间 → 弹出"爽/笑/反转"互动组件
3. 用户点击 → 上报后端 → WebSocket 广播 → 其他用户屏幕出现飘屏特效
4. 剧集结束 → 弹出"剧情续写"入口 → 调用 Doubao 生成分支剧情

## 评分维度对应

| 维度 | 占比 | 实现 |
| - | - | - |
| 功能完整性 | 40% | 列表→播放→AI 识别→互动→广播 全链路 |
| 技术选型 | 30% | Doubao 多模态 + WebSocket 实时同步 |
| 创新探索 | 20% | 情绪飘屏 + AIGC 剧情分支 |
| 文档表达 | 10% | 飞书技术文档 + 录屏 |
