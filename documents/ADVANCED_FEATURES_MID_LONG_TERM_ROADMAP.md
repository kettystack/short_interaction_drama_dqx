
# 高级功能中长期实施路线图

基于 `ADVANCED_FEATURES_TECH_IMPLEMENTATION_PLAN.md` 和当前代码状态整理。原文档回答“这些高级功能应该怎么设计”，本文回答“接下来按什么顺序做，做到什么程度才算可用”。

## 1. 当前状态判断

项目现在已经不是纯方案阶段，已经具备以下基础能力：

- AIGC 插片任务 API、mock provider、播放器插播链路。
- AI 续写 thread/turn 入库，保留 JSON 兜底。
- 高光评测 gold label、precision/recall/F1 接口。
- `/admin` 轻后台入口和基础数据概览。
- 匿名用户、admin token、限流、敏感词审核、模型调用日志骨架。
- 互动事件入库，WebSocket 实时互动。
- effects manifest 骨架和高级功能 smoke 脚本。

当前最大风险不是“功能不存在”，而是三类质量风险：

1. AIGC 插片内容不贴剧情。
2. 高光识别准不准缺少稳定证据。
3. 后台和测试还不足以支持持续运营。

因此中长期路线不要继续盲目堆新按钮，而是先把“剧情上下文、素材选择、质量闸门、人工运营、评测闭环”做扎实。

## 2. 总体策略

建议分三层推进 AIGC 和互动能力。

### 第一层：演示稳定层

目标：答辩或 demo 里不出明显穿帮。

原则：

- mock 插片只能使用同剧同集素材。
- 没有同集素材就拦截，不跨集硬播。
- 后台能看到任务状态和拦截原因。
- 每个主展示剧至少准备 1 集 gold set 和 3 个可解释高光点。

### 第二层：AI 辅助剪辑层

目标：比纯文生视频更稳定，先用真实剧集素材做“AI 检索 + 自动剪辑 + 插片”。

核心思想：

```text
当前剧情上下文
  -> 语义检索同剧/同人物/同场景候选片段
  -> AI 选择最贴合的素材
  -> 自动裁剪 4-8 秒
  -> 转码 HLS
  -> 质量闸门校验
  -> 插播
```

这比直接文生视频更适合短剧项目，因为人物、服装、场景一致性更容易保证。

### 第三层：真实 AIGC 生成层

目标：真正接入视频生成服务，但不让生成结果直接上线。

核心思想：

```text
剧情上下文
  -> 结构化镜头规划
  -> 视频生成 provider
  -> 下载/转码
  -> 多模态质量评估
  -> 人工审核或自动通过
  -> 播放器回填
```

真实生成必须走异步任务，不建议做“用户点了立刻等视频”。视频生成慢、成本高、失败率和风格偏移都不可控，产品上应该用“稍后完成 / 精选插片 / 运营审核”承接。

## 3. AIGC 插片中长期技术方案

### 3.1 先解决“牛头不对马嘴”

当前已做的短期修正：

- `mock provider` 不再跨剧/跨集 fallback。
- 没有同集素材时返回 failed。
- 前端提示“加速包已拦截”，不再自动播错视频。

下一步要做的是把“同集素材”变成可运营资产，而不是只读 `branches`。

新增数据表建议：

```text
clip_assets
  id
  drama_id
  episode_id
  source_video_url
  clip_url
  ts_start
  ts_end
  duration
  characters
  location
  action_tags
  emotion_tags
  visual_tags
  transcript
  embedding_id
  status
  created_at
  updated_at

aigc_quality_checks
  id
  job_id
  clip_url
  context_score
  character_score
  action_score
  style_score
  final_decision
  reasons
  created_at
```

新增目录建议：

```text
backend/app/domains/aigc_video/
  context_builder.py       # 构建剧情上下文
  intent_planner.py        # 从上下文生成结构化插片意图
  asset_resolver.py        # 同剧素材检索和排序
  quality_gate.py          # 生成结果质量闸门
  transcode.py             # 生成/剪辑视频转码
  worker.py                # 异步推进 job

ai_pipeline/
  clip_segmenter.py        # 把原剧切成候选短片段
  clip_indexer.py          # 给片段打标签、摘要、向量
  visual_embedding.py      # 视觉帧向量
```

核心对象：

```python
class AigcGenerationContext(BaseModel):
    episode_id: str
    drama_id: str
    ts_in_video: float
    episode_title: str
    current_highlight: dict | None
    nearby_events: list[dict]
    nearby_captions: list[str]
    branch_path: list[str]
    story_thread_id: str | None
    frame_urls: list[str]

class VideoInsertIntent(BaseModel):
    trigger_type: str
    characters: list[str]
    location: str
    action: str
    emotion: str
    camera_style: str
    duration_seconds: float
    must_include: list[str]
    must_avoid: list[str]

class ClipCandidate(BaseModel):
    clip_id: str
    clip_url: str
    episode_id: str
    ts_start: float
    ts_end: float
    score: float
    match_reasons: list[str]

class QualityGateResult(BaseModel):
    decision: str  # pass/review/reject
    score: float
    reasons: list[str]
```

核心函数输入输出：

```python
async def build_generation_context(
    db: AsyncSession,
    episode_id: str,
    ts_in_video: float,
    highlight_id: int | None,
    story_thread_id: str | None,
) -> AigcGenerationContext:
    """读取剧集、高光、叙事事件、字幕、附近帧，形成生成上下文。"""

async def plan_video_intent(
    context: AigcGenerationContext,
    trigger_type: str,
    user_prompt: str,
) -> VideoInsertIntent:
    """把用户按钮和剧情上下文转成结构化镜头意图。"""

async def resolve_clip_asset(
    db: AsyncSession,
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
) -> ClipCandidate | None:
    """只在同剧、优先同集素材中检索候选片段，返回最匹配 clip。"""

async def validate_clip(
    context: AigcGenerationContext,
    intent: VideoInsertIntent,
    clip_url: str,
) -> QualityGateResult:
    """用规则 + 多模态模型检查人物、场景、动作、风格是否匹配。"""
```

数据流：

```text
用户点击“加速包”
  -> POST /api/aigc-video/jobs
  -> create_job 写入 queued
  -> worker build_generation_context
  -> plan_video_intent
  -> resolve_clip_asset
  -> validate_clip
  -> pass: job.ready + output_video_url
  -> review: job.review_required，后台审核
  -> reject: job.failed，前端提示不插播
```

### 3.2 中期优先做“AI 辅助剪辑”，不要先押注纯生成

原因：

- 短剧人物一致性很重要，纯文生视频容易换脸、换场景、换服装。
- 观众对插片的第一要求是“像这一集”，不是“看起来很 AI”。
- 真实素材检索 + 自动裁剪的成本和稳定性更适合 demo 到小规模产品。

中期能力清单：

1. 批量切片：每集按镜头/字幕切成 3-8 秒候选 clip。
2. 标签化：抽字幕、动作、人物、情绪、高光类型。
3. 向量化：字幕 embedding + 关键帧视觉 embedding。
4. 检索排序：同剧同集 > 同剧近邻集 > 同类型通用素材。
5. 质量闸门：低分不播，进入后台 review。
6. 插片回填：ready 后播放器插播并记录 `aigc_clip_played`。

### 3.3 长期再接真实视频生成 provider

真实 provider 适配器应该放在：

```text
backend/app/domains/aigc_video/providers/
  base.py
  jimeng.py
  mock.py
```

Provider 不直接决定业务，只负责提交、轮询、下载：

```python
class VideoGenerationProvider(Protocol):
    async def submit(self, request: VideoGenerationRequest) -> ProviderJob:
        ...

    async def poll(self, provider_job_id: str) -> ProviderJobStatus:
        ...

    async def download(self, provider_job_id: str, target_dir: Path) -> Path:
        ...
```

真实生成的 job 状态流：

```text
queued
  -> context_ready
  -> intent_ready
  -> submitted
  -> generating
  -> downloading
  -> transcoding
  -> quality_checking
  -> ready / review_required / failed
```

质量闸门必须包含：

- 是否仍是同一部剧的角色/关系。
- 场景是否贴近当前剧情。
- 动作是否符合 trigger_type。
- 是否有明显违和内容。
- 是否存在敏感/低俗/版权风险。
- 时长和竖屏比例是否符合播放器。

## 4. 高光识别评测中长期方案

当前有评测接口，但还需要把它变成日常质量系统。

### 中期目标

每部主展示剧至少做：

- 3 集 gold set。
- 每集 8-15 个 gold label。
- 每次 pipeline 运行后自动输出 precision / recall / F1 / type_accuracy。
- 后台展示 TP / FP / FN 列表。

### 长期目标

让高光识别可以持续迭代：

```text
人工 gold label
  -> 评测 run
  -> 错误样本分类
  -> prompt / 规则 / 模型版本调整
  -> 回归评测
  -> 只有指标不下降才上线
```

建议新增：

```text
backend/tests/test_evaluation_metrics.py
ai_pipeline/evaluation_report.py
documents/HIGHLIGHT_EVALUATION_REPORT.md
```

指标上线门槛建议：

```text
precision >= 0.75
recall >= 0.65
f1 >= 0.70
type_accuracy >= 0.60
严重误触发 <= 每集 2 个
```

## 5. 运营后台中长期方案

后台不要一开始做得很大，先围绕三件事：

1. 高光能修。
2. 插片能审。
3. 分支和素材能配。

### 中期后台页面

```text
/admin
  概览：AIGC 任务、评测结果、待审核数

/admin/episodes/:episodeId/highlights
  高光列表、时间调整、互动类型修改、保存

/admin/episodes/:episodeId/clips
  clip asset 列表、标签编辑、预览、启用/禁用

/admin/aigc/jobs
  任务状态、prompt、输出视频、质量分、审核通过/拒绝

/admin/evaluation
  gold label、评测 run、错误样本
```

### 长期后台能力

- 审核队列：AI 续写、弹幕、AIGC 插片统一审核。
- 审计日志：谁改了高光、分支、素材。
- 模型成本面板：按模型、功能、用户、剧集统计成本。
- 内容发布流：draft -> review -> published -> archived。

## 6. 安全治理和多用户一致性

当前已经有匿名登录和基础限流骨架。中长期建议：

### 中期

- Flutter `ApiClient` 自动带 Authorization。
- admin token 不再写在输入框默认值里，改成本地 secure storage。
- AIGC、AI 续写、弹幕统一走 moderation。
- 互动事件、AIGC job、story thread 使用幂等 key。

### 长期

- Redis Pub/Sub 支持多实例 WebSocket。
- refresh token + device session。
- 内容审核队列。
- model_call_logs 成本统计。
- rate_limit_buckets 定时清理。

关键数据流：

```text
Flutter 登录
  -> anonymous-login
  -> access token 写入 session
  -> 每个 API 自动带 Bearer token
  -> 后端 get_current_user
  -> 普通用户访问自己的数据
  -> admin 访问运营接口
```

## 7. 自动化测试路线

### 中期必须补

```text
backend/tests/
  test_story_chat.py
  test_aigc_video.py
  test_evaluation_metrics.py
  test_interactions.py

flutter_app/test/
  aigc_video_controller_test.dart
  insert_clip_controller_test.dart
```

重点测试：

- AIGC 同集素材才可 ready。
- 无同集素材返回 failed，不返回 output_video_url。
- story chat 选择分支后 turn append，不覆盖历史。
- highlight evaluation 指标计算正确。
- interaction like count 不跳数。

### 长期再做

```text
flutter_app/integration_test/
  player_interaction_flow_test.dart
  ai_story_chat_flow_test.dart
  admin_review_flow_test.dart
```

CI 顺序：

```bash
python3 -m py_compile $(find backend/app -name '*.py')
python3 scripts/advanced_smoke_test.py --base-url http://127.0.0.1:8000
cd flutter_app && flutter analyze --no-pub
cd flutter_app && flutter test
```

## 8. 推荐实施节奏

### 第 0 阶段：现在到答辩前

目标：演示不穿帮。

任务：

1. AIGC mock 只允许同集素材，已完成。
2. 给主展示集补 3 个同集 `clip_assets` 或 branch 素材。
3. 后台展示 AIGC job 的拦截原因和匹配分。
4. 每部主展示剧做 1 集 gold set。
5. 准备一页评测报告：precision / recall / F1。

验收：

- 点击加速包不会播错剧。
- 后台能解释为什么某个任务 failed。
- 有一张高光评测指标表。

### 第 1 阶段：2-4 周

目标：从 mock 进化到 AI 辅助剪辑。

任务：

1. 实现 `clip_assets` 表。
2. 实现 `clip_segmenter.py`，批量切 3-8 秒片段。
3. 实现 `clip_indexer.py`，给 clip 打字幕、标签、embedding。
4. 实现 `asset_resolver.py`，同剧同集优先检索。
5. 实现 `quality_gate.py`，低分进入 review。
6. 后台加 clip 资产管理和 AIGC 审核。

验收：

- 不依赖手工 branch，也能找到贴近当前剧情的短片段。
- 任意一集点击加速包，要么找到同剧合理素材，要么明确拦截。
- 后台能审核通过一个插片再让播放器使用。

### 第 2 阶段：1-2 个月

目标：接真实视频生成 provider。

任务：

1. 完成 `providers/jimeng.py` 或其它真实 provider adapter。
2. 实现 `worker.py` 异步推进任务。
3. 实现下载、转码、封面抽帧。
4. 增加真实生成质量闸门。
5. 增加成本统计和限额。

验收：

- 真实生成任务可以从 queued 到 ready。
- 失败、超时、低质量都会有明确状态。
- ready 视频可以 HLS 播放。
- 后台能看到成本、耗时、质量分。

### 第 3 阶段：2-3 个月以上

目标：产品化和规模化。

任务：

1. Redis Pub/Sub 多实例实时互动。
2. 完整登录、refresh token、权限体系。
3. 内容审核队列和审计日志。
4. A/B 测试互动效果。
5. 高光识别回归评测进入 CI。
6. 音效、动效、haptic 做成完整资产体系。

验收：

- 多用户、多设备数据一致。
- AI 功能有成本上限和安全治理。
- 每次改模型或 prompt 都能跑回归评测。
- 运营可以不改代码完成高光、插片、分支、审核配置。

## 9. 最建议下一步做什么

优先级最高的不是马上接真实视频生成，而是做 `clip_assets + asset_resolver + quality_gate`。

原因：

- 它直接解决“牛头不对马嘴”。
- 它能复用现有剧集素材，成本低。
- 它是未来真实 AIGC 的质量兜底。
- 它能自然接后台审核和评测。

下一步最小代码任务：

```text
1. backend models 增加 ClipAsset / AigcQualityCheck
2. ai_pipeline 增加 clip_segmenter.py
3. backend/app/domains/aigc_video/asset_resolver.py
4. backend/app/domains/aigc_video/quality_gate.py
5. admin 页面增加 clip asset 列表和预览
6. scripts 增加 seed_clip_assets.py
7. tests 增加 test_aigc_video_same_episode_guard.py
```

这样项目会从“有 AI 概念”变成“AI 能在剧情上下文里做稳定决策”。
