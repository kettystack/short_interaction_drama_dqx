# 用「注释驱动」方式让 AI 写出分支互动功能代码

> **核心思路**：先写注释（自然语言意图），让 GitHub Copilot / Cursor / 文心等 AI 工具根据注释补全代码。  
> 这不是魔法，而是一套可复现的提示工程（Prompt Engineering）技巧。

---

## 一、什么是「注释驱动开发」

传统写代码：先想实现 → 直接写代码  
注释驱动写代码：先用注释写清楚「要做什么、数据从哪来、返回什么」→ AI 补全实现

**好处**：
1. 你不需要记住每个 API 的精确语法，只需要说清楚意图
2. 注释本身就是文档，留给后人（包括自己）看
3. AI 补全的代码贴近已有项目风格（因为它看到了文件上下文）

**工具选择**：
- **VS Code + GitHub Copilot**：按 `Tab` 接受单行补全，`Ctrl+Enter` 打开建议面板
- **Cursor**：`Cmd+K` 行内生成，`Cmd+L` 对话式生成
- **两者均支持**：写完注释后直接换行，AI 会自动开始补全

---

## 二、注释写法规范（三段式）

```
# ① 是什么（What）：一句话函数功能
# ② 输入（Input）：参数名 + 类型 + 来源
# ③ 输出（Output/Behavior）：返回什么 / 产生什么副作用
```

越详细，AI 补出来越准。下面通过本项目的实际功能演示。

---

## 三、后端代码（Python · FastAPI · SQLAlchemy）

### 3.1 数据模型 —— `BranchFork` 分叉点表

**你写的注释**：
```python
# 剧情分叉点，记录视频在某个时间戳触发一次用户选择
# 字段：
#   episode_id   - 所属集 ID，外键 episodes.id（字符串，如 "ep_063"）
#   ts_in_video  - 视频内触发时间（秒），Float，加索引便于时间范围查询
#   parent_branch_id - 若此分叉发生在某分支内部，填父 Branch.id；主线上为 null
#   prompt_text  - 显示给用户的问题，如"向云要怎么应对？"
#   branches     - 反向关联 Branch 列表（一对多）
class BranchFork(Base):
```

**AI 补全结果（真实代码）**：
```python
class BranchFork(Base):
    __tablename__ = "branch_forks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float, index=True)
    parent_branch_id: Mapped[int | None] = mapped_column(
        ForeignKey("branches.id"), nullable=True
    )
    prompt_text: Mapped[str] = mapped_column(Text, default="")

    branches: Mapped[list["Branch"]] = relationship(back_populates="fork")
```

> **技巧**：注释里直接写字段名和类型，AI 会把它们翻译成 `mapped_column`。
> 加了"加索引便于查询"这句话，AI 自动加了 `index=True`。

---

### 3.2 数据模型 —— `Branch` 分支视频片段

**你写的注释**：
```python
# 一个可选的分支视频片段，属于某个 BranchFork 的某个选项
# 字段：
#   fork_id       - 所属分叉点 ID（FK）
#   choice_label  - 用户看到的选项标签，如"假意接钱伺机反击"
#   video_url     - 分支视频路径，如 /videos/branches/ep_063_b1.mp4；若空则退化为 AI 文字续集
#   duration      - 视频时长（秒）
#   order_idx     - 选项排列顺序（0、1、2），用于前端按序显示
#   description   - 补充说明，如"来自第64集"，仅前端展示用
#   next_fork_id  - 本分支视频内的下一个分叉点 ID（可空，实现多级剧情树）
class Branch(Base):
```

**AI 补全**：
```python
class Branch(Base):
    __tablename__ = "branches"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fork_id: Mapped[int] = mapped_column(ForeignKey("branch_forks.id"), index=True)
    choice_label: Mapped[str] = mapped_column(String(128))
    video_url: Mapped[str] = mapped_column(String(512), default="")
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    order_idx: Mapped[int] = mapped_column(Integer, default=0)
    description: Mapped[str] = mapped_column(Text, default="")
    next_fork_id: Mapped[int | None] = mapped_column(
        ForeignKey("branch_forks.id"), nullable=True
    )

    fork: Mapped[BranchFork] = relationship(back_populates="branches")
```

---

### 3.3 FastAPI 路由 —— 查询分叉点列表

**你写的注释**：
```python
# GET /api/branches/forks/{episode_id}
# 返回指定集的所有分叉点，每个分叉点含其分支选项列表
# - 使用 selectinload 避免 N+1 查询
# - 按 ts_in_video 升序排列（时间顺序）
# - 每个 fork 内的 branches 按 order_idx 排序
# 返回 list[ForkOut]
@router.get("/forks/{episode_id}", response_model=list[ForkOut])
async def list_forks(episode_id: str, db: AsyncSession = Depends(get_db)):
```

**AI 补全**：
```python
@router.get("/forks/{episode_id}", response_model=list[ForkOut])
async def list_forks(episode_id: str, db: AsyncSession = Depends(get_db)):
    res = await db.execute(
        select(BranchFork)
        .where(BranchFork.episode_id == episode_id)
        .options(selectinload(BranchFork.branches))
        .order_by(BranchFork.ts_in_video)
    )
    forks = res.scalars().all()
    for f in forks:
        f.branches.sort(key=lambda b: b.order_idx)
    return forks
```

---

### 3.4 FastAPI 路由 —— 批量导入分支配置

**你写的注释**：
```python
# POST /api/branches/seed
# 从 {data_root}/branches.json 读取配置，批量导入分叉点和分支
# JSON 结构：{ "forks": [ { episode_id, ts_in_video, prompt_text, branches: [...] } ] }
# 
# 处理步骤：
#   1. 读取并解析 JSON 文件，文件不存在返回 404
#   2. 校验所有 episode_id 在数据库中存在，不存在返回 400
#   3. 清空旧数据：先删 branches 表，再删 branch_forks 表（外键顺序）
#   4. 按顺序插入新数据，同时创建对应的 BranchFork 和 Branch 对象
#   5. 提交事务，返回 { "forks": N, "branches": M }
@router.post("/seed")
async def seed_branches(db: AsyncSession = Depends(get_db)):
```

**AI 补全**：
```python
@router.post("/seed")
async def seed_branches(db: AsyncSession = Depends(get_db)):
    path = Path(settings.data_root) / "branches.json"
    if not path.exists():
        raise HTTPException(404, f"no branches config: {path}")

    payload = json.loads(path.read_text(encoding="utf-8"))

    # 步骤 2：校验 episode_id
    episode_ids = {f["episode_id"] for f in payload.get("forks", [])}
    for eid in episode_ids:
        if not await db.get(Episode, eid):
            raise HTTPException(400, f"episode not exists: {eid}")

    # 步骤 3：清空旧数据（外键顺序：先子后父）
    await db.execute(Branch.__table__.delete())
    await db.execute(BranchFork.__table__.delete())
    await db.flush()

    fork_count = branch_count = 0
    for f in payload.get("forks", []):
        fork = BranchFork(
            episode_id=f["episode_id"],
            ts_in_video=float(f["ts_in_video"]),
            parent_branch_id=f.get("parent_branch_id"),
            prompt_text=f.get("prompt_text", ""),
        )
        db.add(fork)
        await db.flush()  # 获得自增 id
        for b in f.get("branches", []):
            db.add(Branch(
                fork_id=fork.id,
                choice_label=b["choice_label"],
                video_url=b.get("video_url", ""),
                duration=float(b.get("duration", 0)),
                order_idx=int(b.get("order_idx", 0)),
                description=b.get("description", ""),
            ))
            branch_count += 1
        fork_count += 1

    await db.commit()
    return {"forks": fork_count, "branches": branch_count}
```

> **技巧**：注释里写了「步骤 1/2/3/4/5」，AI 会对应生成分步代码，可读性极好。

---

## 四、Flutter 客户端代码（Dart）

### 4.1 数据模型 —— `BranchFork` + `BranchOption`

**你写的注释**：
```dart
// 从后端 /api/branches/forks/{ep} 返回的分叉点数据
// 字段：
//   id          - 分叉点 ID
//   episodeId   - 所属集 ID
//   tsTrigger   - 触发时间（秒），与 ts_in_video 对应
//   question    - 显示给用户的问题文案（对应 prompt_text）
//   options     - 该分叉点的所有可选分支（List<BranchOption>）
// fromJson: 兼容 branches 和 options 两个 key（后端历史兼容）
class BranchFork {
```

**AI 补全**：
```dart
class BranchFork {
  final int id;
  final String episodeId;
  final double tsTrigger;
  final String question;
  final List<BranchOption> options;

  BranchFork({
    required this.id,
    required this.episodeId,
    required this.tsTrigger,
    required this.question,
    required this.options,
  });

  factory BranchFork.fromJson(Map<String, dynamic> j) => BranchFork(
        id: j['id'],
        episodeId: j['episode_id'],
        tsTrigger: (j['ts_in_video'] ?? 0).toDouble(),
        question: j['prompt_text'] ?? '',
        options: ((j['options'] ?? j['branches'] ?? []) as List)
            .map((e) => BranchOption.fromJson(e))
            .toList(),
      );
}

// 一个分支选项（对应后端 Branch 表）
// 字段：
//   id          - 分支 ID
//   label       - 选项按钮显示文案
//   description - 补充说明（可空）
//   videoUrl    - 分支视频路径；null 或空字符串表示退化为 AI 文字续集
//   votes       - 其他用户选择该分支的票数（实时）
class BranchOption {
```

---

### 4.2 API 客户端 —— 请求分叉点数据

**你写的注释**：
```dart
// 请求指定集的所有分叉点（含选项列表）
// 调用 GET /api/branches/forks/{episodeId}
// 若请求失败，返回空列表（不抛出，由调用方决定是否用 fallback）
// 返回 List<BranchFork>
Future<List<BranchFork>> getForks(String episodeId) async {
```

**AI 补全**：
```dart
Future<List<BranchFork>> getForks(String episodeId) async {
  try {
    final res = await _dio.get('/api/branches/forks/$episodeId');
    return (res.data as List)
        .map((e) => BranchFork.fromJson(e))
        .toList();
  } catch (_) {
    return [];
  }
}
```

---

### 4.3 控制器 —— 分叉点检测（`_matchFork`）

**你写的注释**：
```dart
// 时间轴每帧调用，检测当前播放位置 seconds 是否命中某个分叉点
// 规则：
//   - 若已有 pendingFork（等待用户选择），直接返回，不再检测
//   - 遍历 forks 列表，找到满足以下条件的第一个：
//       ① 该 fork.id 不在 _handledForkIds 中（本次播放未处理过）
//       ② |seconds - fork.tsTrigger| < 0.6（在 600ms 时间窗口内）
//   - 命中则将 pendingFork 设置为该分叉点，break
// 副作用：修改 pendingFork，后续 notifyListeners 由调用方 onTick 统一触发
void _matchFork(double seconds) {
```

**AI 补全**：
```dart
void _matchFork(double seconds) {
  if (pendingFork != null) return;
  for (final f in forks) {
    if (!_handledForkIds.contains(f.id) &&
        (seconds - f.tsTrigger).abs() < 0.6) {
      pendingFork = f;
      break;
    }
  }
}
```

> **技巧**：`① ② ③` 的枚举写法非常有效，AI 会逐条转换为 `&&` 条件。

---

### 4.4 控制器 —— 用户做出分支选择（`chooseBranch`）

**你写的注释**：
```dart
// 用户选择了一个分支选项 opt，处理分支切换逻辑
// 步骤：
//   1. 将 pendingFork.id 加入 _handledForkIds（防止 seek 回来重复弹出）
//   2. 若 opt.videoUrl 非空，更新 currentBranchId = opt.id.toString()
//   3. 清空 pendingFork = null，触发 UI 隐藏选项卡
//   4. 调用 notifyListeners
//   5. 向后端异步上报 branch_pick 事件（POST /api/interactions），
//      payload 包含 fork_id, branch_id, choice_label, has_video
// 注意：此方法为 async，上报失败不影响本地 UI 状态
Future<void> chooseBranch(BranchOption opt) async {
```

**AI 补全**：
```dart
Future<void> chooseBranch(BranchOption opt) async {
  if (_disposed) return;
  final fork = pendingFork;
  if (fork == null) return;

  // 步骤 1-4
  _handledForkIds.add(fork.id);
  if (opt.videoUrl != null && opt.videoUrl!.isNotEmpty) {
    currentBranchId = opt.id.toString();
  }
  pendingFork = null;
  _safeNotify();

  // 步骤 5：异步上报，失败静默
  if (episodeId != null) {
    await _submitInteraction(
      action: 'branch_pick',
      ts: fork.tsTrigger,
      effect: 'branch_choice',
      payload: {
        'fork_id': fork.id,
        'branch_id': opt.id,
        'choice_label': opt.label,
        'choice_description': opt.description,
        'has_video': opt.videoUrl != null && opt.videoUrl!.isNotEmpty,
      },
    );
  }
}
```

---

### 4.5 顶层控制器 —— 分支选择触发视频切换（`PlayerController.chooseBranch`）

**你写的注释**：
```dart
// 接管来自 UI 层的分支选择事件
// 1. 委托 interaction.chooseBranch(option) 更新互动状态
// 2. 若 option.videoUrl 非空：
//    a. 调用 playback.open(videoUrl, autoplay:true) 切换视频源
//    b. 调用 danmaku.resetTo(Duration.zero) 重置弹幕时间轴（新视频从头开始）
// 3. 若 videoUrl 为空：不切流，由 UI 层（player_page）负责打开 AiBranchSheet
Future<void> chooseBranch(BranchOption option) async {
```

**AI 补全**：
```dart
Future<void> chooseBranch(BranchOption option) async {
  await interaction.chooseBranch(option);
  if (option.videoUrl != null && option.videoUrl!.isNotEmpty) {
    await playback.open(option.videoUrl!, autoplay: true);
    danmaku.resetTo(Duration.zero);
  }
}
```

---

### 4.6 UI 组件 —— 分支选项卡（`BranchChoiceOverlay`）

**你写的注释**：
```dart
// 全屏半透明遮罩，展示分叉点的问题和所有选项按钮
// Props:
//   fork   - BranchFork，含问题文案和选项列表
//   onPick - 用户点击某个选项时回调，传入 BranchOption
//   onSkip - 用户点击「跳过」时回调
// 布局：
//   - 背景：black54 半透明，居中纵向排列
//   - 顶部：分叉路口图标 + "剧情分岔"副标题 + 问题文本（大字加粗）
//   - 中部：每个 option 一个按钮（label 大字 + description 小字）
//   - 底部：跳过按钮（TextButton，低调样式）
// 样式：使用 AppColors.accentMint 作为主题色
class BranchChoiceOverlay extends StatelessWidget {
```

**AI 补全**：
```dart
class BranchChoiceOverlay extends StatelessWidget {
  final BranchFork fork;
  final ValueChanged<BranchOption> onPick;
  final VoidCallback onSkip;

  const BranchChoiceOverlay({
    super.key,
    required this.fork,
    required this.onPick,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alt_route, color: AppColors.accentMint, size: 36),
            const SizedBox(height: 12),
            Text('剧情分岔',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 12,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 6),
            Text(fork.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 22),
            ...fork.options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        side: BorderSide(
                            color: AppColors.accentMint.withValues(alpha: .5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => onPick(o),
                      child: Column(children: [
                        Text(o.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        if (o.description.isNotEmpty)
                          Text(o.description,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                      ]),
                    ),
                  ),
                )),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onSkip,
              child: const Text('跳过本次抉择',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 五、注释写好后的实操流程（VS Code + Copilot）

```
1. 打开目标文件（如 interaction_controller.dart）

2. 光标放到你要新增函数的位置，写注释：
   // 检测当前播放位置是否命中分叉点
   // - pendingFork 非空时直接 return
   // - 遍历 forks，找到 |seconds - f.tsTrigger| < 0.6 且未处理过的
   // - 命中则 pendingFork = f，break

3. 写函数签名的第一个字，例如：
   void _m    ← 这时 Copilot 开始补全

4. 按 Tab 接受补全，或 Ctrl+Enter 看所有建议

5. 如果补全不对，在注释里加更多细节再试
```

**Cursor 用法（更推荐）**：
```
1. 写好注释后，选中注释文字
2. Cmd+K，输入：「根据上面的注释实现这个函数，
   遵循文件里已有的代码风格，使用 _safeNotify() 而不是 notifyListeners()」
3. Cursor 会直接在注释下方插入代码
```

---

## 六、注释质量 vs 补全质量对比

| 注释质量 | 写法示例 | AI 补全效果 |
|---|---|---|
| ❌ 太笼统 | `// 检测分叉点` | 补出来只有骨架，逻辑不对 |
| ⚠️ 一般 | `// 在时间轴上检测是否到了分叉点时间` | 大致方向对，细节缺失 |
| ✅ 精确 | `// 遍历 forks，找到 |seconds - f.tsTrigger| < 0.6 且 f.id 不在 _handledForkIds 中的，赋给 pendingFork` | 几乎不需要改 |
| ✅✅ 有步骤 | 用 `步骤1/2/3` 或 `①②③` 列出每步 | 代码结构清晰，各步骤有注释 |

---

## 七、针对本项目三个模块的「注释模板」

### 后端新增一个 API 路由

```python
# [HTTP方法] /api/[路径]
# 功能：一句话描述
# 
# 请求参数：
#   - path param: xxx (类型，说明)
#   - query param: yyy (类型，默认值，说明)
# 
# 处理步骤：
#   1. ...
#   2. ...
# 
# 返回：{ "字段名": 类型说明 }
# 错误：404 if xxx not found
@router.get("/path/{param}")
async def my_endpoint(param: str, db: AsyncSession = Depends(get_db)):
```

### Flutter 控制器新增方法

```dart
// 方法功能一句话
// 
// 入参：
//   xxx - 类型，用途
// 
// 步骤：
//   1. 先检查 _disposed，已销毁直接 return
//   2. ...
//   3. 调用 _safeNotify() 通知 UI 更新
// 
// 副作用：修改 xxx 字段；异步上报不影响本地状态
Future<void> myMethod(SomeType xxx) async {
```

### Flutter Widget 新增组件

```dart
// 描述：这个 Widget 的视觉效果和交互
// 
// Props:
//   xxx - 类型，用途
//   onXxx - 事件回调，什么时候触发
// 
// 布局：
//   - 外层：Container with [背景颜色]
//   - 内层：Column 纵向排列 [元素1] + [元素2]
// 
// 样式：使用 AppColors.xxx 作为主色
class MyWidget extends StatelessWidget {
```

---

## 八、完整操作演示：从零添加「分支视频结尾返回主线」功能

这个功能目前未实现，用注释驱动方式添加：

**第一步**：在 `InteractionController` 里写注释

```dart
// 分支视频播放结束时调用（由 PlaybackController 的 completed 事件触发）
// 功能：清除 currentBranchId，回到主线播放状态
// 步骤：
//   1. currentBranchId = null
//   2. 将当前 forks 中与已完成分支相关的 fork 加入 _handledForkIds（防止回主线后重触发）
//   3. _safeNotify()
void onBranchVideoCompleted() {
```

**第二步**：在 `PlaybackController` 里写注释

```dart
// 监听 player 的 completed 事件（视频播到结尾）
// 当 completed == true 时，调用传入的 onCompleted 回调
// 在 PlayerController 初始化时传入 interaction.onBranchVideoCompleted
void listenCompleted(VoidCallback onCompleted) {
```

**第三步**：在 `PlayerController` 初始化方法里写注释，把两者串起来

```dart
// 订阅分支视频结束事件
// 当 currentBranchId 非空且视频播到结尾时，调用 interaction.onBranchVideoCompleted()
// 然后 playback.open(episode.videoUrl) 切回主线，seek 到 fork.tsTrigger + 1（跳过触发点）
```

按 `Cmd+K` 或等待 Copilot 补全，三块代码都能自动生成并拼在一起。

---

## 九、总结

| 做什么 | 怎么写注释 |
|---|---|
| 数据模型 | 列出每个字段名+类型+用途，提到外键/索引 |
| API 路由 | 写 HTTP 方法 + 路径 + 步骤 + 返回格式 |
| 控制器方法 | 写步骤编号 + 副作用 + 异常处理策略 |
| UI 组件 | 写视觉结构（外层/内层）+ 样式色值 + 事件回调 |

**最重要的一条**：注释是给 AI 看的，也是给人看的。注释越具体，补出的代码越准，review 也越容易。
