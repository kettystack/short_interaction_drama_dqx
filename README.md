# Short Drama Interaction

短剧即时互动系统：用 AI 自动识别短剧里的爽点、反转、泪点和悬念，在播放器里触发弹幕、情绪按钮、分支选择、AI 剧情续写和个性化分支视频。

这个仓库是一个完整的全栈 Demo，包含 Flutter 客户端、FastAPI 后端、离线 AI 高光识别流水线、互动数据配置和技术文档。大体积视频、HLS 切片、生成视频和本地密钥不上传 GitHub，只保留可以复现逻辑的代码与轻量 JSON 配置。

## 项目亮点

| 模块 | 能力 |
| - | - |
| 短剧播放器 | Flutter 竖屏沉浸式播放、剧集列表、播放控制、选集、收藏、会员页 |
| 即时互动 | 高光时间点触发互动按钮、情绪飘屏、礼物动效、弹幕设置和 WebSocket 广播 |
| AI 高光识别 | FFmpeg 抽帧、Whisper 字幕、音频峰值/镜头切点召回、Doubao 多模态判断剧情节点 |
| 分支剧情 | 后端生成剧情分支，客户端弹出选择面板，支持剧情续写和互动剧状态流转 |
| 个性化分支视频 | 根据当前剧情、高光、用户意图生成分支视频任务，并做质量评估与发布控制 |
| 后台与数据 | 用户、VIP、推荐、Feed、Analytics、Admin、资产管理等接口骨架 |

## MVP 闭环

1. 用户进入 Flutter App，浏览短剧列表并打开剧集。
2. 后端提供剧集元数据、视频地址、高光点、分支配置和互动状态。
3. 播放器播放到高光时间窗时，前端展示情绪互动、弹幕、礼物或分支选择。
4. 用户点击互动后，上报 FastAPI，后端通过 WebSocket 同步给同一剧集的其他用户。
5. 剧情节点结束后，可以进入 AI 剧情续写、互动剧分支或个性化分支视频体验。
6. 离线 AI Pipeline 可以从原始 mp4 重新抽帧、识别字幕、高光并产出 JSON，供后端导入。

## 技术栈

| 层 | 技术 |
| - | - |
| 客户端 | Flutter 3 / Dart，支持 Android、iOS、macOS、Web 工程骨架 |
| 后端 | FastAPI、SQLAlchemy async、asyncpg、Redis、WebSocket、Pydantic Settings |
| 数据库 | PostgreSQL 16、Redis 7 |
| AI Pipeline | FFmpeg / ffprobe、Whisper、PySceneDetect、Doubao / Volcengine Ark 多模态 |
| 视频服务 | FastAPI Range Streaming、HLS 静态分发、生成媒体分发 |
| 本地编排 | Docker Compose、Python venv、Flutter CLI |

## 仓库结构

```text
.
├── backend/                 # FastAPI 服务端
│   ├── app/api/             # HTTP / WebSocket 路由
│   ├── app/domains/         # 业务域：互动、分支视频、剧情续写、安全、资产等
│   ├── app/scripts/         # seed 与媒体处理脚本
│   └── tests/               # 后端测试
├── flutter_app/             # Flutter 跨平台客户端
│   ├── lib/core/            # 配置、路由、主题、会话
│   ├── lib/data/            # API Client 与数据模型
│   └── lib/features/        # 首页、播放器、互动剧、分支视频、会员等页面
├── ai_pipeline/             # 离线 AI 高光识别流水线
├── data/                    # 只提交轻量 JSON 配置，不提交视频与生成资源
├── scripts/                 # smoke test、批处理、预生成工具
├── documents/               # PRD、技术方案、验收和设计文档
├── docker-compose.yml       # Postgres / Redis / 可选后端容器
├── LOCAL_RUN_GUIDE.md       # 本地运行详细说明
└── DELIVERY_DEMO_GUIDE.md   # 演示与答辩说明
```

## GitHub 上传策略

这个仓库已经通过 `.gitignore` 排除了本地敏感和大体积内容：

| 不上传 | 原因 |
| - | - |
| `backend/.env`、`ai_pipeline/.env`、`.env*` | 真实 API Key、Token、数据库连接等只放本机 |
| `data/hls/`、`data/generated/`、`data/frames/`、`data/highlights/` | HLS 切片、生成视频、抽帧和批处理产物体积很大 |
| `*.mp4`、`*.mov`、`*.mkv`、`*.webm`、`*.ts`、`*.m3u8` | 原始视频和切片不适合进普通 Git 仓库 |
| `.venv/`、`__pycache__/`、`build/`、`Pods/`、`.dart_tool/` | 本地依赖和构建产物可重新生成 |
| `*.log`、`*.pid`、`.DS_Store`、`.vscode/` | 运行时和编辑器状态 |

仓库里保留的 `backend/.env.example` 和 `ai_pipeline/.env.example` 是模板，可以复制成 `.env` 后在本机填写真实密钥。

## 快速开始

下面命令假设你已经进入项目根目录：

```bash
cd short_intercation_drama
```

### 1. 安装前置依赖

建议准备：

- Docker Desktop
- Python 3.11
- Flutter SDK 3.x
- FFmpeg / ffprobe
- 可选：Whisper 所需的本地 Python 依赖

macOS 可用：

```bash
brew install ffmpeg python@3.11
flutter doctor
```

### 2. 启动 PostgreSQL 和 Redis

```bash
docker compose up -d postgres redis
docker compose ps
```

默认端口：

| 服务 | 地址 |
| - | - |
| FastAPI | `http://127.0.0.1:8000` |
| PostgreSQL | `localhost:5432` |
| Redis | `localhost:6379` |

### 3. 配置后端环境变量

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

基础 Demo 不强制填写 AI Key，但建议检查这些配置：

```env
DATABASE_URL=postgresql+asyncpg://sdi:sdi@localhost:5432/sdi
REDIS_URL=redis://localhost:6379/0
PUBLIC_BASE_URL=http://127.0.0.1:8000

# 真实短剧视频不在 GitHub，需要指向你本机的视频目录
VIDEO_ROOT=/absolute/path/to/beipaixunbao
TIANXIADYI_VIDEO_ROOT=/absolute/path/to/tianxiadyi
SHIBASUITAINAINAI_VIDEO_ROOT=/absolute/path/to/shibasuitainainai
DATA_ROOT=../data

# AI 能力需要时再填写，切勿提交真实值
ARK_API_KEY=
ARK_ENDPOINT=
DOUBAO_API_KEY=
DOUBAO_ENDPOINT=
STORY_CHAT_API_KEY=
STORY_CHAT_ENDPOINT=
```

### 4. 启动后端

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

验证：

```bash
curl http://127.0.0.1:8000/
curl http://127.0.0.1:8000/api/episodes
```

API 文档：

```text
http://127.0.0.1:8000/docs
```

### 5. 初始化 Demo 数据

另开一个终端：

```bash
cd backend
source .venv/bin/activate
python -m app.scripts.seed_episodes
curl -X POST http://127.0.0.1:8000/api/highlights/import/ep_063
curl -X POST http://127.0.0.1:8000/api/branches/seed
```

如果本机没有原始视频目录，剧集 seed 会缺少可播放视频，但后端接口和大部分互动配置仍可查看。视频相关资源需要自己放在 `.env` 指定的 `VIDEO_ROOT` / `TIANXIADYI_VIDEO_ROOT` / `SHIBASUITAINAINAI_VIDEO_ROOT` 下。

### 6. 启动 Flutter 客户端

```bash
cd flutter_app
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android 模拟器如果使用默认 `127.0.0.1`，客户端会自动替换为 `10.0.2.2`。真机调试请改成电脑的局域网 IP：

```bash
flutter run -d android --dart-define=API_BASE_URL=http://192.168.x.x:8000
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

## AI Pipeline

AI Pipeline 用于把原始短剧 mp4 转成高光 JSON。它会组合镜头切点、音频峰值、字幕上下文和多模态模型判断，输出可导入后端的结构化高光点。

```bash
cd ai_pipeline
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

单集处理：

```bash
python run_pipeline.py \
  --video /absolute/path/to/episode.mp4 \
  --episode-id ep_063 \
  --out ../data/highlights/ep_063.json
```

批量处理：

```bash
python run_pipeline.py --batch /absolute/path/to/videos --out-dir ../data/highlights
```

注意：`data/highlights/` 默认不上传 GitHub，因为它是可再生成产物。如果要共享少量样例，可以单独挑选轻量 JSON 并确认不包含敏感信息。

## 常用接口

| 接口 | 说明 |
| - | - |
| `GET /` | 健康检查 |
| `GET /api/episodes` | 剧集列表 |
| `GET /api/highlights/{episode_id}` | 剧集高光点 |
| `POST /api/highlights/import/{episode_id}` | 从本地 JSON 导入高光点 |
| `POST /api/branches/seed` | 导入剧情分支配置 |
| `GET /api/branches/forks/{episode_id}` | 查询分支配置 |
| `WS /api/interactions/ws/{episode_id}` | 剧集互动 WebSocket |
| `GET /videos/{file_path}` | 原始视频 Range Streaming |
| `GET /hls/{file_path}` | HLS 文件服务 |
| `GET /generated/{file_path}` | AIGC 生成媒体文件服务 |

更多接口以 `http://127.0.0.1:8000/docs` 为准。

## 常用脚本

| 脚本 | 用途 |
| - | - |
| `backend/app/scripts/seed_episodes.py` | 扫描本地视频目录并写入剧集表 |
| `backend/app/scripts/seed_tianxiadyi.py` | 导入《天下第一》相关剧集/配置 |
| `backend/app/scripts/seed_danmaku_highlights.py` | 导入弹幕和高光演示数据 |
| `scripts/branch_video_smoke_test.py` | 分支视频链路 smoke test |
| `scripts/advanced_smoke_test.py` | 高级功能 smoke test |
| `scripts/build_hls.sh` | 生成 HLS 切片 |
| `scripts/pregen_aigc_boosts.py` | 预生成 AIGC boost 资源 |
| `scripts/pregen_branch_video_catalog.py` | 预生成分支视频目录 |

## 开发建议

推荐日常开发使用 3 个终端：

```bash
# Terminal 1: 基础设施
docker compose up -d postgres redis

# Terminal 2: 后端
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Terminal 3: Flutter
cd flutter_app
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

如果要跑完整容器版后端：

```bash
DOUBAO_API_KEY=xxx DOUBAO_ENDPOINT=xxx docker compose --profile full up --build
```

## 常见问题

| 问题 | 处理方式 |
| - | - |
| `404 video not found` | 检查 `.env` 里的 `VIDEO_ROOT` 是否指向真实 mp4 目录 |
| Flutter 真机访问不到后端 | `API_BASE_URL` 改成电脑局域网 IP，并确认防火墙允许 `8000` |
| `curl /api/episodes` 返回空 | 先运行 `python -m app.scripts.seed_episodes` |
| 高光点为空 | 运行 `POST /api/highlights/import/{episode_id}`，或先用 AI Pipeline 生成 JSON |
| AI 续写不可用 | 检查 `ARK_API_KEY` / `DOUBAO_API_KEY` / endpoint 配置；基础互动 Demo 可不填 |
| GitHub 上传太大 | 确认视频、HLS、生成媒体都在 `.gitignore` 范围内，不要手动 `git add -f` |

## 文档索引

| 文档 | 内容 |
| - | - |
| `LOCAL_RUN_GUIDE.md` | 更完整的本地启动、seed、运行和排障步骤 |
| `DELIVERY_DEMO_GUIDE.md` | 演示路线、录屏脚本和交付说明 |
| `BRANCH_TECH_DEEPDIVE.md` | 分支剧情和互动链路技术细节 |
| `AI_HIGHLIGHT_RECOGNITION_RESEARCH.md` | AI 高光识别方案调研 |
| `documents/README.md` | documents 目录索引 |
| `ai_pipeline/README.md` | AI Pipeline 单独说明 |
| `flutter_app/README.md` | Flutter 工程说明 |

## 安全提醒

- 不要提交真实 `.env`、API Key、Token、私钥或数据库密码。
- 如果误提交了密钥，即使后来删除，也应立即去服务商后台轮换密钥。
- GitHub 仓库建议保持 Private，演示时只展示代码和 `.env.example`。
- 大视频文件建议放本地、对象存储或 Git LFS，不建议直接进普通 Git 历史。
