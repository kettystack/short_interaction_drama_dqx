# 答辩录屏与技术说明

> 项目：基于短剧剧情的即时互动激发  
> 当前交付重点：天下第一 6-24 接入、太奶奶 1-26 高光覆盖、剧情分支 / AI 续写、录屏说明

## 1. 当前可演示范围

| 剧 | 剧集覆盖 | 播放形式 | 弹幕 | 高光 |
| - | - | - | - | - |
| 北派寻宝笔记 | ep_063-ep_081 | HLS | 已接入 | 已接入 |
| 天下第一纨绔 | txy_001-txy_024 | HLS | 1-5 有弹幕 | 1-24 有高光 |
| 十八岁太奶奶驾到 | sbtnn_001-sbtnn_026 | MP4 Range | 1-5 有弹幕 | 1-26 有高光 |

说明：圈选弹幕 CSV 只覆盖每部剧前 5 集，所以 6 集以后不再伪造弹幕；后续集使用题材化剧情高光节拍，让播放器仍能触发互动特效、右侧高光、剧情分支等能力。

## 2. 本地启动

### 后端

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend
PYTHONPATH=. .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### Flutter macOS 客户端

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/flutter_app
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

若只需要构建可打开的 macOS App：

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/flutter_app
flutter build macos --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000
open build/macos/Build/Products/Debug/sdi_flutter.app
```

## 3. 录屏脚本

建议录屏控制在 6-8 分钟，按下面顺序走。

### 片段 A：整体入口和剧集覆盖

1. 打开 Flutter App 首页。
2. 展示三部剧入口：北派寻宝笔记、天下第一纨绔、十八岁太奶奶驾到。
3. 进入天下第一，展示剧集列表已扩到 24 集。
4. 点开 txy_006 或 txy_024，说明 6-24 使用 HLS，能正常播放。

可讲点：从单剧 demo 扩为多剧内容池；天下第一 6-24 已完成 HLS 接入和剧集注册。

### 片段 B：弹幕 + 高光互动

1. 切到 txy_001 或 sbtnn_001。
2. 播放时展示弹幕贯穿后半段，没有再出现后半段无弹幕的问题。
3. 点击右侧互动按钮或高光触发区域，展示飘字、情绪特效、互动计数变化。

可讲点：弹幕接口支持 `density=all&limit=60000`，解决密度截断；高光命中后驱动即时互动，而不是单纯播放视频。

### 片段 C：太奶奶 26 集高光覆盖

1. 进入十八岁太奶奶驾到。
2. 展示剧集列表到 sbtnn_026。
3. 打开 sbtnn_024 或 sbtnn_026，展示 6 集以后的高光也能触发互动提示。

可讲点：1-5 集使用真实弹幕峰值抽取高光；6-26 集没有弹幕源，因此用题材化叙事高光生成器生成剧情节拍，再用 densify 补足氛围互动点。

### 片段 D：剧情分支与 AI 续写

1. 打开 sbtnn_001。
2. 播放到约 52 秒，展示分叉点：`家族众人还没认出太奶奶，你希望她怎么破局？`
3. 展示三个分支：
   - 当场亮辈分镇住众人
   - 装糊涂套出幕后黑手
   - 先护住孙辈再反击
4. 选择一个分支，展示真实视频片段播放。
5. 点击 AI 剧情续写入口，展示 Doubao 生成的一段续写和 3 个后续选项。

可讲点：分支视频来自圈选剧真实片段切片；AI 续写使用 Doubao，后端有本地兜底，保证现场网络异常时也能返回可演示文本。

## 4. 技术实现说明

### 4.1 内容接入

- `scripts/build_hls.sh`：将天下第一源视频转 HLS，输出到 `data/hls/txy_001` 到 `txy_024`。
- `backend/app/scripts/seed_tianxiadyi.py`：注册天下第一 24 集，并导入前 5 集弹幕。
- `backend/app/scripts/seed_shibasuitainainai.py`：注册太奶奶 26 集，并导入前 5 集弹幕。
- `backend/app/config.py`：配置真实视频根目录，支持 `/videos/tianxiadyi/...` 和 `/videos/shibasuitainainai/...`。

### 4.2 高光生成

- `backend/app/scripts/seed_danmaku_highlights.py`：前 5 集基于弹幕峰值生成高光，类型覆盖年龄反差、护短撑腰、打脸爽点、家族冲突等剧情标签。
- `scripts/gen_narrative_highlights.py`：无弹幕集的叙事高光生成器，读取真实视频时长，按题材生成互动节拍。
- `scripts/densify_highlights.py`：补充低强度氛围高光，避免长时间无互动。
- `/api/highlights/import/{episode_id}`：将 JSON 高光导入 PostgreSQL。

### 4.3 互动与实时同步

- `/api/interactions`：记录用户点击行为。
- `/api/interactions/ws/{episode_id}`：同集 WebSocket 房间广播互动。
- `/api/interactions/summary/{episode_id}`：返回互动总数，供前端按钮计数展示。
- Flutter 端根据当前播放时间匹配高光，触发情绪特效、右侧互动按钮和飘屏反馈。

### 4.4 剧情分支 / AI 续写

- `data/branches.json`：分叉点和选项配置。
- `scripts/build_branches.py`：从真实剧集切出分支视频片段。
- `/api/branches/seed`：把分叉点导入数据库。
- `/api/branches/forks/{episode_id}`：播放页获取当前剧集分叉点。
- `/api/interactions/branch`：调用 Doubao 生成续写；Doubao 不可用时返回本地兜底续写。

## 5. 验证命令

```bash
cd /Users/daiqixu/Desktop/duanjujifa/short-drama-interaction/backend

# 后端语法检查
PYTHONPATH=. .venv/bin/python -m compileall app

# 太奶奶 26 集可见
.venv/bin/python - <<'PY'
import httpx
with httpx.Client(trust_env=False, timeout=30) as c:
    print(len(c.get('http://127.0.0.1:8000/api/episodes?drama_id=shibasuitainainai').json()))
    print(len(c.get('http://127.0.0.1:8000/api/highlights/sbtnn_026').json()))
    print(len(c.get('http://127.0.0.1:8000/api/branches/forks/sbtnn_001').json()))
PY
```

预期结果：

```text
26
6
1
```

## 6. 本次增量文件

| 文件 | 作用 |
| - | - |
| `scripts/gen_narrative_highlights.py` | 为无弹幕集批量生成题材化叙事高光 |
| `scripts/build_branches.py` | 从真实剧集剪出分支视频片段 |
| `data/highlights/sbtnn_006.json` - `sbtnn_026.json` | 太奶奶 6-26 集高光数据 |
| `data/branches.json` | 新增太奶奶 sbtnn_001 分叉点 |
| `data/branches_config.json` | 新增太奶奶分支切片配置 |
| `backend/app/services/ai_service.py` | AI 续写失败兜底 |
| `backend/app/config.py` | 修正天下第一默认视频根路径 |

## 7. 注意事项

- 不展示或提交任何 API Key；录屏里只说明使用 Doubao，不展示 `.env`。
- 6 集以后没有真实弹幕源，因此不要声称这些集有真实弹幕；应表述为“真实视频 + AI/规则生成高光节拍”。
- 如果 curl 命令后面要换行，使用 Python `httpx` 或 `curl -w '\n'`；避免把分号拼进 URL 导致 `episode not exists` 的假 404。
