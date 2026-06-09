# AI 代码补全技巧 + 项目 Debug 完整指南

> 两部分合并：  
> **Part 1** — 怎么更好地用 AI（Copilot / Cursor）写代码  
> **Part 2** — 这个项目（Python 后端 + Flutter 客户端）怎么调试

---

# Part 1：怎么更好地用 AI 补全代码

## 1.1 核心认知：AI 补全的三个层次

```
层次 1 · 单行补全    —— 你打开头几个字，AI 猜下一行      （最基础）
层次 2 · 函数补全    —— 你写注释 / 函数签名，AI 补全实现   （日常主力）
层次 3 · 对话式生成   —— 你描述需求，AI 一次写出多个文件    （Cursor 最强）
```

本项目用到的 AI 工具：
- **GitHub Copilot**（VS Code 内置）：Tab 补全、`Ctrl+I` 行内 chat
- **Cursor**：`Cmd+K` 行内生成、`Cmd+L` 侧边对话、`Cmd+Shift+I` 全文件编辑

---

## 1.2 让 AI 读懂项目上下文（最重要）

AI 补全的质量 90% 取决于它是否理解了你项目的模式。  
**方法：在同一文件里，先让 AI 看到已有的代码再写新代码。**

### 做法 A：把相似的已有代码放在同一文件前面

比如在 `branches.py` 里已有 `list_forks`，要新写 `get_fork_detail`：
```python
# ← AI 看到上面 list_forks 的写法后，自动用同样风格补全下面这个
@router.get("/forks/{fork_id}/detail", response_model=ForkDetailOut)
async def get_fork_detail(fork_id: int, db: AsyncSession = Depends(get_db)):
    # 查询指定 fork_id 的分叉点，eagerly load branches，不存在返回 404
```

### 做法 B：Copilot Chat 里先粘贴参考代码

```
# 在 Copilot Chat 里说：
"参考这段代码的风格写一个新函数：
[粘贴 list_forks 的实现]
现在帮我写 delete_fork(fork_id)，删除前先检查 branches 是否为空"
```

### 做法 C：用 `@workspace` 或 `@file` 引用（Copilot Chat）

```
@file:backend/app/api/branches.py
在这个文件里新增一个 PATCH /forks/{id} 接口，用于更新 prompt_text
```

---

## 1.3 五种高效注释写法

### 写法 1：步骤式（最万能）

```python
# POST /api/branches/forks/{fork_id}/vote
# 用户对某个分支选项投票
# 步骤：
#   1. 查询 fork，不存在返回 404
#   2. 查询目标 branch，校验 branch.fork_id == fork_id
#   3. branch.votes += 1，update
#   4. 返回 { "branch_id": id, "votes": new_votes }
@router.post("/forks/{fork_id}/vote")
async def vote_branch(fork_id: int, branch_id: int, db: ...):
```

### 写法 2：IO 声明式（数据流清晰时用）

```dart
// 输入：forks: List<BranchFork>，seconds: double（当前播放秒数）
// 输出：第一个满足 |seconds - f.tsTrigger| < 0.6 且未处理过的 fork；没有则返回 null
// 副作用：无（纯查询，不修改状态）
BranchFork? _findTriggeredFork(List<BranchFork> forks, double seconds) {
```

### 写法 3：对比参考式（有相似已有实现时）

```dart
// 与 _matchFork 类似，但检测的是 highlight 而非 fork
// 区别：返回命中的 Highlight 对象，且允许同时命中多个（取 intensity 最高的）
Highlight? _matchHighlight(double seconds) {
```

### 写法 4：边界条件式（容易出 bug 的地方）

```python
# 解析 branches.json 中的 ts_in_video 字段
# 注意边界：
#   - 可能是 int（如 56）或 float（如 56.5），统一转 float
#   - 不能为负数，否则跳过该条数据
#   - 缺失时默认 0.0（不报错）
def parse_ts(raw) -> float:
```

### 写法 5：数据结构驱动式（写 fromJson / toJson 时）

```dart
// 从后端 /api/branches/forks/{ep} 的 JSON 构造
// JSON 字段映射（注意：后端用下划线，前端用驼峰）：
//   id           → id (int)
//   episode_id   → episodeId (String)
//   ts_in_video  → tsTrigger (double)
//   prompt_text  → question (String)
//   branches     → options (List<BranchOption>)  ← 兼容旧字段名 options
factory BranchFork.fromJson(Map<String, dynamic> j) =>
```

---

## 1.4 Cursor 三个核心操作

| 操作 | 快捷键 | 用途 | 示例 |
|---|---|---|---|
| 行内生成 | `Cmd+K` | 在光标处生成或替换代码 | 光标放在函数上，Cmd+K 输入「加入防 dispose 检查」 |
| 侧边对话 | `Cmd+L` | 和 AI 对话，可引用文件 | 「帮我看看 _matchFork 有没有并发问题」 |
| 全文件编辑 | `Cmd+Shift+I` | 批量修改整个文件 | 「把所有 notifyListeners() 改成 _safeNotify()」 |

### 实际工作流示例：添加「分支结束后返回主线」

```
Step 1 · Cmd+L 开对话：
「@file:flutter_app/lib/features/player/controllers/player_controller.dart
  帮我实现：当分支视频播放完成（completed event）后，
  自动切回主线视频并 seek 到 fork 触发点 +1 秒。
  遵循文件里已有的 _bufferingSubscription 订阅风格。」

Step 2 · AI 生成代码草稿，检查逻辑后 Apply

Step 3 · Cmd+K 微调：选中生成的代码，Cmd+K 输入
「确保 _disposed 判断在最前面，seek 前先 pause」
```

---

## 1.5 容易踩的坑及对策

| 坑 | 现象 | 对策 |
|---|---|---|
| AI 补了个不存在的方法 | 代码看起来对，但运行报 `NoSuchMethodError` | 补全后立刻 `flutter analyze` 或 Python `compileall` |
| AI 用了错误的异步写法 | `await` 丢失，或在 `StatefulWidget` 里直接用 `async initState` | 告诉 AI「这个 widget 用的是 ChangeNotifier + AnimatedBuilder，不用 setState」 |
| AI 没有遵循项目风格 | 用了 `setState` 而不是 `notifyListeners`，用了 `print` 而不是 `_log.d` | 在 chat 里加一句「遵循已有代码风格，日志用 `_log.d`，状态更新用 `_safeNotify()`」 |
| 生成代码太长需要拆分 | AI 一次写了 200 行 | 要求「先只写函数签名和步骤注释，不要实现」再逐步补全 |

---

# Part 2：项目 Debug 完整指南

## 2.1 项目组成速查

```
short-drama-interaction/
├── backend/          ← Python 3.12 + FastAPI + SQLAlchemy (async) + PostgreSQL
│   ├── .venv/        ← 虚拟环境（已有）
│   ├── .env          ← 数据库 URL、API Key 等
│   └── app/
│       ├── main.py   ← FastAPI 入口
│       ├── models.py ← ORM 模型
│       └── api/      ← 路由（branches / highlights / interactions...）
│
└── flutter_app/      ← Flutter 3.x，目标平台：macOS / iOS / Android / Web
    └── lib/
        ├── data/          ← ApiClient + 数据模型
        └── features/
            └── player/    ← 播放器 + 互动控制器
```

---

## 2.2 后端调试

### 方法 A：最快 — 直接带 reload 跑，看终端日志

```bash
cd short-drama-interaction/backend
PYTHONPATH=. .venv/bin/uvicorn app.main:app \
  --host 127.0.0.1 --port 8000 \
  --reload \                    # 改代码自动重启
  --log-level debug             # 打印所有 SQL 和请求
```

终端里会看到：
```
INFO:     127.0.0.1:54321 - "GET /api/branches/forks/ep_063 HTTP/1.1" 200 OK
DEBUG:    sqlalchemy.engine: SELECT branch_forks.id ...
```

### 方法 B：VS Code 断点调试（推荐，可以在代码行打断点）

**第一步：安装 debugpy**

```bash
cd short-drama-interaction/backend
.venv/bin/pip install debugpy
```

**第二步：创建 `.vscode/launch.json`（项目根目录，已自动生成，见下方）**

配置文件路径：`short-drama-interaction/.vscode/launch.json`

**第三步：在 VS Code 里按 `F5` 选择 "Backend: FastAPI (debug)" 启动**

打断点方式：
- 点击代码左侧行号区域 → 出现红点 = 断点
- 请求到达时自动暂停，可查看变量值、调用栈

### 方法 C：快速验证 API（curl 脚本）

```bash
# 查看某集分叉点
curl -s http://127.0.0.1:8000/api/branches/forks/ep_063 | python3 -m json.tool

# 导入分支数据
curl -X POST http://127.0.0.1:8000/api/branches/seed -w "\n"

# 查看集信息
curl -s http://127.0.0.1:8000/api/episodes/ep_063 | python3 -m json.tool

# 查看某集高光
curl -s http://127.0.0.1:8000/api/highlights/ep_063 | python3 -m json.tool
```

### 方法 D：在代码里加临时日志

```python
# 在 backend/app/api/branches.py 里任意位置加
import logging
logger = logging.getLogger(__name__)

# 使用
logger.debug("fork list: %s", [f.id for f in forks])
logger.info("seed done: forks=%d branches=%d", fork_count, branch_count)
logger.error("episode not found: %s", eid)
```

用 `--log-level debug` 启动时，`DEBUG` 级别也会打印出来。

### 后端常见报错 & 解法

| 报错 | 原因 | 解法 |
|---|---|---|
| `connection refused` | PostgreSQL 没跑 | `brew services start postgresql@16` 或 `docker compose up db` |
| `episode not exists: ep_063` | seed 前集不在数据库 | 先 `curl -X POST .../api/episodes/seed_beipaixunbao` |
| `404 no branches config` | `data/branches.json` 不存在 | 检查 `DATA_ROOT` 配置，确认文件路径 |
| `sqlalchemy.exc.IntegrityError` | 外键约束违反（如 branch 引用了不存在的 fork） | seed 时先清库：`DELETE FROM branches; DELETE FROM branch_forks;` |
| `422 Unprocessable Entity` | 请求体格式不对 | 看响应 body 里的 `detail` 字段，通常有字段名和错误原因 |

---

## 2.3 Flutter 调试

### 方法 A：VS Code 断点调试（推荐）

**配置文件已在 `.vscode/launch.json` 里准备好（见下方）**

按 `F5` → 选 "Flutter: macOS (debug)" → 等待编译 → App 自动启动  
代码里点行号打断点，触发到时 VS Code 自动暂停。

### 方法 B：命令行 run（带热重载）

```bash
cd short-drama-interaction/flutter_app

# macOS 调试（最常用）
flutter run -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --debug

# 热重载：r
# 热重启：R
# 打开 DevTools：按 v 或运行时看终端的 DevTools URL
```

### 方法 C：Dart DevTools（最强可视化工具）

启动 app 后，终端会打印：
```
An Observatory debugger and profiler on macOS is available at:
http://127.0.0.1:50123/xxxxx/
The Flutter DevTools debugger and profiler on macOS is available at:
http://127.0.0.1:9100?uri=...
```

复制 DevTools URL 到 Chrome 浏览器，可以：
- **Widget Inspector**：点击任意 Widget 查看属性树（找 UI 问题神器）
- **Timeline**：查看帧率，找卡顿根源
- **Logging**：查看所有 `_log.d(...)` 输出
- **Memory**：查看内存占用和泄漏

### 方法 D：项目内日志系统（`logger` 包）

本项目用 `logger` 包，已在各控制器里集成：

```dart
// interaction_controller.dart 里已有
final _log = Logger();

// 用法（从详到简）
_log.d('fork triggered: id=${f.id} ts=${f.tsTrigger}');   // debug（最详）
_log.i('branch chosen: ${opt.label}');                      // info
_log.w('videoUrl empty, falling back to AI story');         // warning
_log.e('API error', error: e, stackTrace: st);              // error
```

**在哪里加日志最有效**：

| 位置 | 加什么 |
|---|---|
| `InteractionController.loadFor()` | 打印加载到的 forks 数量和每个 ts |
| `_matchFork()` | 打印每次检测到的 seconds 和命中情况 |
| `chooseBranch()` | 打印选了哪个 option 和 videoUrl |
| `PlaybackController.open()` | 打印最终传给 media_kit 的 URL |
| `ApiClient.getForks()` | 打印原始 JSON 响应 |

### Flutter 常见报错 & 解法

| 报错 | 原因 | 解法 |
|---|---|---|
| `Connection refused` | 后端没跑 | 先启动后端 |
| 视频黑屏 / 无法播放 | URL 路径有中文没编码 | `AppConfig.absoluteUrl()` 会自动处理，确认调用了它 |
| 分叉选项不弹出 | forks 未加载 / 时间戳不对 | 在 `_matchFork` 加 `_log.d`，看 seconds 和 f.tsTrigger |
| 选择后视频没切换 | `videoUrl` 为空 | 检查 `data/branches.json` 的 `video_url` 字段 |
| `type 'Null' is not a subtype of type 'String'` | fromJson 里字段缺失 | 在 `ApiClient.getForks` 里 `_log.d(res.data.toString())` 看原始 JSON |
| 弹幕切换分支后错位 | `danmaku.resetTo` 没调用 | 检查 `PlayerController.chooseBranch()` |

---

## 2.4 全栈联调调试流程（排查数据流）

当「功能没反应」时，按这个顺序逐层排查：

```
问题：分叉选项没有弹出

① 确认后端有数据
   curl http://127.0.0.1:8000/api/branches/forks/ep_063
   → 没数据？POST /api/branches/seed 重新导入

② 确认 Flutter 拿到了数据
   在 ApiClient.getForks() 里加 _log.d(res.data.toString())
   → 没打印？检查网络连接和 API_BASE_URL

③ 确认 forks 列表非空
   在 InteractionController.loadFor() 里加
   _log.d('forks loaded: ${forks.length} → ${forks.map((f) => f.tsTrigger)}')

④ 确认时间轴 tick 在调用 _matchFork
   在 onTick() 开头加 _log.d('tick: $seconds')
   → 如果没打印，检查 _positionSubscription 是否建立

⑤ 确认分叉点时间戳匹配
   在 _matchFork() 里加
   _log.d('checking fork id=${f.id} ts=${f.tsTrigger} diff=${(seconds - f.tsTrigger).abs()}')
   → diff > 0.6 就不会触发，调整 branches.json 里的 ts_in_video

⑥ 确认 pendingFork 被设置，UI 渲染了
   在 _matchFork 命中后加 _log.i('pendingFork set: ${f.id}')
   → 如果设置了但 UI 没渲染，检查 AnimatedBuilder 监听的是 interaction controller
```

---

## 2.5 数据库调试（PostgreSQL）

```bash
# 连接到本地数据库
psql postgresql://sdi:sdi@localhost:5432/sdi

# 常用查询
\dt                                          -- 列出所有表
SELECT * FROM branch_forks;                  -- 查看所有分叉点
SELECT * FROM branches WHERE fork_id = 1;    -- 查看某个分叉点的分支
SELECT id, title, episode_no FROM episodes ORDER BY episode_no;  -- 查看集列表

# 清空分支数据重新导入
DELETE FROM branches;
DELETE FROM branch_forks;
\q
curl -X POST http://127.0.0.1:8000/api/branches/seed -w "\n"
```

---

## 2.6 视频文件调试

```bash
# 确认分支视频文件存在
ls short-drama-interaction/data/videos/branches/

# 确认 ffmpeg 可以读取分支视频
ffprobe short-drama-interaction/data/videos/branches/ep_063_b1.mp4 2>&1 | grep -E 'Duration|Video|Audio'

# 手动剪辑一段分支视频（从第64集 1:10 开始，取 31 秒）
ffmpeg -i juben/beipaixunbao/branches/第64集.mp4 \
  -ss 00:01:10 -t 31 -c copy \
  short-drama-interaction/data/videos/branches/ep_063_b1.mp4
```

---

# 附录：已配置的 VS Code 调试配置

> 文件：`short-drama-interaction/.vscode/launch.json`（在下一节自动创建）

包含以下配置：
1. **Backend: FastAPI (debug)** — Python debugpy，支持断点
2. **Flutter: macOS (debug)** — Flutter macOS 调试，自动注入 `API_BASE_URL`
3. **Flutter: Chrome (web debug)** — Web 调试
4. **Full Stack** — 同时启动后端 + Flutter（compound configuration）
