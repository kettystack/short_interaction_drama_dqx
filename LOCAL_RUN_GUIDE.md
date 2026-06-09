# Short Drama Interaction 本地运行说明

这份文档说明当前 workspace 里几个核心程序怎么跑起来：

- FastAPI 服务端
- Flutter 跨平台客户端（Android / iOS / macOS）
- 可选的 AI Pipeline

文档按两个场景组织：

1. 首次初始化
2. 日常开发启动

如果你只想尽快把现有 demo 跑起来，优先看“最小可运行路径”。

## 1. 当前工程路径与端口

当前 workspace 的实际路径关系如下：

| 项目 | 路径 / 端口 |
| - | - |
| workspace 根目录 | `/Users/daiqixu/Desktop/duanjujifa` |
| 项目根目录 | `/Users/daiqixu/Desktop/duanjujifa/short-drama-interaction` |
| 北派视频目录 | `/Users/daiqixu/Desktop/duanjujifa/juben/beipaixunbao` |
| 天下第一视频目录 | `/Users/daiqixu/Desktop/duanjujifa/juben/tianxiadyi` |
| 太奶奶视频目录 | `/Users/daiqixu/Desktop/duanjujifa/juben/shibasuitainainai` |
| 后端端口 | `8000` |
| PostgreSQL | `5432` |
| Redis | `6379` |
| Flutter App | `short-drama-interaction/flutter_app` |

Flutter App 后端地址通过 `--dart-define=API_BASE_URL=http://127.0.0.1:8000` 注入，真机开发替换为局域网 IP。

## 2. 前置依赖

建议机器上先具备以下工具：

- Docker Desktop
- Flutter SDK 3.x（`flutter doctor` 需全绿）
- Python 3.11
- ffmpeg / ffprobe

```bash
brew install ffmpeg python@3.11
```

## 3. 最小可运行路径

如果你的目标是先把当前 demo 跑起来并验证 `ep_063`：

1. 启动 `postgres` 和 `redis`
2. 启动 FastAPI 后端
3. 运行一次剧集 seed / 高光导入 / 分支 seed
4. 运行 Flutter App（macOS 本地调试或打 APK 真机）

最小必需命令如下。

### 3.1 启动基础设施

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction
docker compose up -d postgres redis
```

可用下面的命令确认容器状态：

```bash
docker compose ps
```

### 3.2 启动后端

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

后端起来后，先用浏览器或 curl 验证：

```bash
curl http://127.0.0.1:8000/
curl http://127.0.0.1:8000/api/episodes
```

### 3.3 初始化数据

另开一个终端执行：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
source .venv/bin/activate
python -m app.scripts.seed_episodes
curl -X POST http://127.0.0.1:8000/api/highlights/import/ep_063
curl -X POST http://127.0.0.1:8000/api/branches/seed
```

执行完成后，建议确认：

```bash
curl http://127.0.0.1:8000/api/episodes | head
curl http://127.0.0.1:8000/api/highlights/ep_063 | head
curl http://127.0.0.1:8000/api/branches/forks/ep_063 | head
```

### 3.4 启动 Flutter App

macOS 本地调试（推荐开发时用）：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/flutter_app
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

构建 Android debug APK（真机，替换成局域网 IP）：

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

构建好的 APK 在 `build/app/outputs/flutter-apk/app-debug.apk`。

## 4. 首次初始化详解

这一节适合第一次在新机器或新 workspace 上完整搭建。

### 4.1 后端 `.env` 配置

首次运行建议先复制一份环境文件：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
cp .env.example .env
```

然后至少确认下面这些字段：

```env
DATABASE_URL=postgresql+asyncpg://sdi:sdi@localhost:5432/sdi
REDIS_URL=redis://localhost:6379/0

# 这两个只有 AI 剧情续写需要；基础播放/互动/分支视频不依赖它们
DOUBAO_API_KEY=
DOUBAO_ENDPOINT=

# 建议写绝对路径，最稳
VIDEO_ROOT=/Users/daiqixu/Desktop/duanjujifa/beipaixunbao
DATA_ROOT=/Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/data
```

注意：

- `VIDEO_ROOT` 如果写错，`/videos/...` 会直接返回 `404 video root not found` 或 `404 video not found`
- `DOUBAO_API_KEY` / `DOUBAO_ENDPOINT` 不填也能跑基础 demo；AI 剧情续写会优先调用 Doubao，调用失败时返回本地兜底续写

### 4.2 数据库初始化说明

后端启动时会自动执行 `init_db()`，自动建表；但不会自动灌入剧集数据和高光数据。

也就是说：

- `uvicorn` 负责建表
- `seed_episodes` 负责把本地 mp4 灌入 `episodes` 表
- `POST /api/highlights/import/{episode_id}` 负责把 `data/highlights/*.json` 导入数据库
- `POST /api/branches/seed` 负责把 `data/branches.json` 导入数据库

### 4.3 剧集 seed

剧集 seed 脚本会扫描 `VIDEO_ROOT` 目录下的 `第*.mp4`，自动生成：

- `ep_063`
- `ep_064`
- `ep_065`
- ...

命令：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
source .venv/bin/activate
python -m app.scripts.seed_episodes
```

如果 Web 列表页显示“暂无剧集，请先运行 seed_episodes 脚本”，就是这一步还没做。

### 4.4 高光导入

当前后端支持按集导入高光 JSON：

```bash
curl -X POST http://127.0.0.1:8000/api/highlights/import/ep_063
```

如果你想把 `data/highlights` 目录里已有 JSON 都导入，可以手动逐集执行，或者按自己的习惯写个循环脚本。

### 4.5 分支导入

当前分支配置文件是：

- `data/branches.json`

导入命令：

```bash
curl -X POST http://127.0.0.1:8000/api/branches/seed
```

## 5. 日常开发启动顺序

日常开发时，推荐固定用 3 个终端：

### 终端 1：基础设施

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction
docker compose up -d postgres redis
```

### 终端 2：后端

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 终端 3：Flutter App

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/flutter_app
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## 6. Flutter 客户端怎么跑

### 6.1 macOS 模拟器 / 本地调试

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/flutter_app
flutter pub get
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 6.2 Android APK（真机）

```bash
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.x.x:8000
# APK 在 build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 6.3 iOS 真机

```bash
flutter run -d <你的设备名> --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

### 6.4 常见问题

- **Flutter App 打开后列表为空**：检查后端是否在 8000 端口运行
- **视频 404**：检查 `backend/.env` 里的 `VIDEO_ROOT`
- **API 请求失败**：确认 `API_BASE_URL` 序列化到了对的主机 IP

## 7. 服务端怎么跑

### 7.1 本地开发模式

推荐开发模式直接用 `uvicorn --reload`：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

优点：

- 改代码立即重载
- 问题定位最直接
- 不用每次重建 Docker 镜像

### 7.2 Docker 启完整后端

如果你想连后端容器也一起跑，可以用 compose 的 `full` profile：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction
DOUBAO_API_KEY=xxx DOUBAO_ENDPOINT=xxx docker compose --profile full up --build
```

但当前本地开发还是更推荐 `uvicorn --reload`。

### 7.3 服务端健康检查

```bash
curl http://127.0.0.1:8000/
curl http://127.0.0.1:8000/api/episodes
curl http://127.0.0.1:8000/api/highlights/ep_063
curl http://127.0.0.1:8000/api/branches/forks/ep_063
curl -I http://127.0.0.1:8000/videos/第63集.mp4
```

如果需要验证视频 seek 是否正常，建议看是否返回 `Accept-Ranges: bytes`，或者直接用 Range 请求测试：

```bash
curl -I -H 'Range: bytes=0-1023' http://127.0.0.1:8000/videos/branches/ep_063_b1.mp4
```

## 8. AI Pipeline 怎么跑

AI Pipeline 不是主链路运行必需项，但在你要重新生成高光点或分支片段时会用到。

### 8.1 重新生成某一集高光 JSON

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/ai_pipeline
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python run_pipeline.py \
  --video ../../beipaixunbao/第63集.mp4 \
  --episode-id ep_063 \
  --out ../data/highlights/ep_063.json
```

生成完以后再导入数据库：

```bash
curl -X POST http://127.0.0.1:8000/api/highlights/import/ep_063
```

### 8.2 批量跑目录下所有 mp4

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/ai_pipeline
source .venv/bin/activate
python run_pipeline.py \
  --batch ../../beipaixunbao \
  --out-dir ../data/highlights
```

### 8.3 重新剪分支视频并生成 `branches.json`

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction
python ai_pipeline/cut_branches.py
curl -X POST http://127.0.0.1:8000/api/branches/seed
```

注意：当前 `ai_pipeline/cut_branches.py` 里 `VIDEO_ROOT` 还是写死的本地绝对路径。如果项目目录变化，需要同步调整这个脚本。

## 10. 常见问题

### 10.1 Flutter App 打开后列表为空

说明 `episodes` 表没有数据。执行：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
source .venv/bin/activate
python -m app.scripts.seed_episodes
```

### 10.2 点击播放后视频 404

优先检查：

1. `backend/.env` 里的 `VIDEO_ROOT` 是否指向真实视频目录
2. `beipaixunbao/第63集.mp4` 是否存在
3. 后端是不是从正确的 `.env` 读到了配置

### 10.3 "AI 剧情续写"失败

需要在 `backend/.env` 里补齐：

```env
DOUBAO_API_KEY=...
DOUBAO_ENDPOINT=...
```

## 11. 建议的下一步

当前项目已经具备：

- Flutter 跨平台客户端（Android / iOS / macOS）
- 后端可运行
- AI Pipeline 可批量处理

最值得优先做的下一步：

- `scripts/dev_up.sh`：一键启动 postgres / redis / backend
- `scripts/seed_demo.sh`：一键执行 `seed_episodes`、导入 `ep_063` 高光、seed 分支
- 去掉 `ai_pipeline/cut_branches.py` 里的硬编码路径，改为环境变量
