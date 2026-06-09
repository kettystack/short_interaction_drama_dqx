# 未实现高级功能技术实现方案

对应缺口：AIGC 视频插入、AI 高光识别评测、人工运营/审核后台、生产级安全治理、多端多用户持久一致性、自动化端到端测试、音效资源和完整互动资产包。

本文按“可以直接开工”的粒度写：需要实现什么功能、目录结构怎么放、接口输入输出是什么、函数如何设计、变量和数据流怎么走。

## 总体架构

### 后端目录建议

```text
backend/app/
  api/
    aigc_video.py          # AIGC 视频生成任务 API
    admin.py               # 运营后台 CRUD / 审核 API
    evaluation.py          # 高光识别评测 API
    auth.py                # 登录 / token / 当前用户 API
    assets.py              # 互动动效和音效资产 API
  domains/
    aigc_video/
      schemas.py
      repository.py
      service.py
      providers/
        base.py
        jimeng.py          # 即梦或其他视频生成服务适配器
        mock.py            # 本地演示/测试用 provider
      worker.py            # 轮询 provider、转码、回填资产
      prompt_builder.py
    evaluation/
      schemas.py
      repository.py
      metrics.py
      service.py
    admin/
      schemas.py
      service.py
    security/
      auth.py
      rate_limit.py
      moderation.py
      cost_tracker.py
      audit.py
    assets/
      schemas.py
      repository.py
      service.py
    story_chat/
      db_repository.py     # 替换当前 JSON 文件存储
  tests/
    e2e/
      test_player_flow.py
      test_story_chat_flow.py
      test_ws_multi_user.py
```

### Flutter 目录建议

```text
flutter_app/lib/
  core/
    auth_session.dart
    secure_storage.dart
    request_id.dart
  data/
    admin_api_client.dart
    models.dart
  features/
    aigc_video/
      aigc_video_controller.dart
      widgets/aigc_boost_button.dart
      widgets/aigc_job_sheet.dart
      widgets/generated_clip_banner.dart
    admin/
      admin_page.dart
      widgets/highlight_editor.dart
      widgets/branch_editor.dart
      widgets/review_queue.dart
      widgets/evaluation_dashboard.dart
    player/
      controllers/insert_clip_controller.dart
    effects/
      effect_asset_registry.dart
      interaction_sound_controller.dart
      widgets/effect_preview_panel.dart
  integration_test/
    player_interaction_flow_test.dart
    story_chat_flow_test.dart
```

### 数据库新增表建议

```text
users
device_sessions
aigc_video_jobs
generated_clip_assets
highlight_gold_labels
highlight_eval_runs
highlight_eval_items
content_review_items
moderation_logs
model_call_logs
rate_limit_buckets
story_threads
story_turns
interaction_effect_assets
asset_usage_events
audit_logs
```

现有表可以继续复用：

- `episodes`：剧集主表
- `episode_assets`：可扩展为 HLS、生成视频、封面等统一资产表
- `transcode_jobs`：生成视频完成后进入转码流程
- `highlights`：AI 高光点
- `branch_forks` / `branches`：分支点和分支视频
- `interaction_events`：点赞、评论、互动、AIGC 插入、音效触发等事件
- `playback_events`：播放行为埋点

## 4. AIGC 视频插入玩法

### 目标功能

用户在剧情高光或剧尾看到“加速包”“反杀预告”“甜蜜补帧”等按钮，点击后触发一个 AIGC 视频生成任务。生成完成后，播放器把生成视频作为临时插片播放，播放完自动回到原剧集进度。

### MVP 版本

第一版不必真的实时等文生视频，可以分两层：

1. `mock provider`：返回预置生成视频，保证演示稳定。
2. `real provider`：接入即梦/其他视频生成 API，异步生成，失败时回退到 mock。

这样答辩时能展示完整链路，同时技术方案里能说明真实接入方式。

### 后端数据模型

新增 `AigcVideoJob`：

```python
class AigcVideoJob(Base):
    __tablename__ = "aigc_video_jobs"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float, default=0.0)
    trigger_type: Mapped[str] = mapped_column(String(32))  # boost/rescue/revenge/sugar/finale
    prompt: Mapped[str] = mapped_column(Text)
    source_context: Mapped[dict] = mapped_column(JSON, default=dict)
    provider: Mapped[str] = mapped_column(String(32), default="mock")
    provider_job_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="queued", index=True)
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    source_video_url: Mapped[str] = mapped_column(String(512), default="")
    output_video_url: Mapped[str] = mapped_column(String(512), default="")
    cover_url: Mapped[str] = mapped_column(String(512), default="")
    error_message: Mapped[str] = mapped_column(Text, default="")
    cost_cents: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
```

状态流转：

```text
queued -> prompt_ready -> submitted -> generating -> downloading -> transcoding -> ready
                                                   -> failed
                                                   -> expired
```

### API 设计

#### 创建生成任务

```http
POST /api/aigc-video/jobs
```

输入：

```json
{
  "episode_id": "ep_063",
  "user_id": "u_001",
  "ts_in_video": 83.5,
  "trigger_type": "boost",
  "user_prompt": "汽车加速去营救女主",
  "style_code": "short_drama_punchy",
  "highlight_id": 12,
  "story_thread_id": "thread_ep_063_83000_xxx"
}
```

输出：

```json
{
  "job_id": "aigc_ep_063_83500_ab12",
  "episode_id": "ep_063",
  "status": "queued",
  "progress": 0,
  "poll_url": "/api/aigc-video/jobs/aigc_ep_063_83500_ab12"
}
```

#### 查询生成任务

```http
GET /api/aigc-video/jobs/{job_id}
```

输出：

```json
{
  "job_id": "aigc_ep_063_83500_ab12",
  "status": "ready",
  "progress": 1,
  "output_video_url": "/videos/aigc/aigc_ep_063_83500_ab12.mp4",
  "hls_url": "/hls/aigc/aigc_ep_063_83500_ab12/master.m3u8",
  "cover_url": "/covers/aigc/aigc_ep_063_83500_ab12.jpg",
  "duration": 6.2,
  "insert_mode": "pause_main_then_play_clip",
  "resume_at": 83.5
}
```

#### 运营侧重试/取消任务

```http
POST /api/aigc-video/jobs/{job_id}/retry
POST /api/aigc-video/jobs/{job_id}/cancel
```

### 核心函数 IO

```python
class AigcVideoService:
    async def create_job(self, payload: AigcVideoJobCreateIn, user: CurrentUser) -> AigcVideoJobOut:
        """创建 AIGC 视频任务，构造 prompt，写入 DB，提交后台 worker。"""

    async def get_job(self, job_id: str, user: CurrentUser) -> AigcVideoJobOut:
        """查询任务状态。普通用户只能查自己的任务，admin 可查全部。"""

    async def advance_job(self, job_id: str) -> AigcVideoJobOut:
        """worker 调用：推进 queued/submitted/generating/downloading/transcoding 状态。"""

    async def attach_asset(self, job: AigcVideoJob, local_path: Path) -> EpisodeAssetOut:
        """把生成视频登记到 episode_assets 或 generated_clip_assets。"""
```

Provider 抽象：

```python
class VideoGenerationProvider(Protocol):
    async def submit(self, request: VideoGenerationRequest) -> ProviderJob:
        """提交生成任务，返回 provider_job_id。"""

    async def poll(self, provider_job_id: str) -> ProviderJobStatus:
        """查询第三方任务进度。"""

    async def download(self, provider_job_id: str, target_dir: Path) -> Path:
        """下载生成视频到本地。"""
```

Prompt builder：

```python
def build_aigc_video_prompt(
    episode: Episode,
    highlight: Highlight | None,
    narrative_context: BranchGenerationContext,
    trigger_type: str,
    user_prompt: str,
    style_code: str,
) -> str:
    """
    输出给视频生成模型的中文镜头 prompt。
    要包含角色、场景、动作、镜头、时长、风格、禁止项。
    """
```

### Flutter 数据流

```text
用户点击“加速包”
  -> AigcVideoController.createJob()
  -> ApiClient.createAigcVideoJob()
  -> 显示 AigcJobSheet(status/progress)
  -> 每 2s 轮询 getAigcVideoJob()
  -> ready 后 InsertClipController.playGeneratedClip()
  -> 暂停主视频，记录 resumeAt
  -> 播放生成 clip
  -> clip ended 后恢复主视频 seekTo(resumeAt)
  -> postInteraction(action="aigc_clip_played")
```

Flutter controller：

```dart
class AigcVideoController extends ChangeNotifier {
  AigcVideoController(this._api);

  AigcVideoJob? currentJob;
  bool isCreating = false;
  Timer? _pollTimer;

  Future<void> createJob({
    required String episodeId,
    required double tsInVideo,
    required String triggerType,
    int? highlightId,
    String userPrompt = '',
  });

  Future<void> pollJob(String jobId);
  void stopPolling();
}
```

播放器插片控制：

```dart
class InsertClipController extends ChangeNotifier {
  bool isPlayingInsertedClip = false;
  Duration? resumePosition;
  String? currentClipUrl;

  Future<void> playInsertedClip({
    required PlaybackController playback,
    required String clipUrl,
    required Duration resumeAt,
  });

  Future<void> resumeMainVideo(PlaybackController playback);
}
```

### 关键变量

| 变量 | 来源 | 用途 |
| --- | --- | --- |
| `episode_id` | 播放器当前剧集 | 绑定生成任务和回填资产 |
| `ts_in_video` | 播放进度 | 确定插入点和上下文 |
| `highlight_id` | 当前高光点 | 构造 prompt 证据 |
| `story_thread_id` | AI 续写 thread | 让生成视频继承剧情分支上下文 |
| `trigger_type` | 按钮类型 | 决定 prompt 模板和 UI |
| `job.status` | 后端任务状态 | 前端展示和轮询 |
| `output_video_url` | 生成/转码结果 | 播放器插片播放 |
| `resume_at` | 创建任务时播放进度 | 插片播放后恢复 |

## 5. AI 高光识别效果评测

### 目标功能

把“AI 识别准不准”变成可量化结果：每集建立人工 gold set，和 pipeline 产出的 `highlights` 做对比，输出 precision、recall、F1、时间命中 IoU、类型准确率、误触发样例。

### Gold Set 数据结构

新增 `highlight_gold_labels`：

```python
class HighlightGoldLabel(Base):
    __tablename__ = "highlight_gold_labels"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_start: Mapped[float] = mapped_column(Float)
    ts_end: Mapped[float] = mapped_column(Float)
    type: Mapped[str] = mapped_column(String(32))
    interaction: Mapped[str] = mapped_column(String(32))
    description: Mapped[str] = mapped_column(Text, default="")
    annotator_id: Mapped[str] = mapped_column(String(64), default="admin")
    confidence: Mapped[float] = mapped_column(Float, default=1.0)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

新增 `highlight_eval_runs` / `highlight_eval_items`：

```python
class HighlightEvalRun(Base):
    __tablename__ = "highlight_eval_runs"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    pipeline_version: Mapped[str] = mapped_column(String(64))
    iou_threshold: Mapped[float] = mapped_column(Float, default=0.3)
    precision: Mapped[float] = mapped_column(Float, default=0.0)
    recall: Mapped[float] = mapped_column(Float, default=0.0)
    f1: Mapped[float] = mapped_column(Float, default=0.0)
    type_accuracy: Mapped[float] = mapped_column(Float, default=0.0)
    false_positive_count: Mapped[int] = mapped_column(Integer, default=0)
    false_negative_count: Mapped[int] = mapped_column(Integer, default=0)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

### API 设计

#### 创建/更新人工标签

```http
POST /api/evaluation/gold-labels
PUT  /api/evaluation/gold-labels/{label_id}
GET  /api/evaluation/gold-labels/{episode_id}
DELETE /api/evaluation/gold-labels/{label_id}
```

输入：

```json
{
  "episode_id": "ep_063",
  "ts_start": 35.2,
  "ts_end": 41.8,
  "type": "剧情悬念",
  "interaction": "炸裂",
  "description": "向云发现笔记暗线",
  "confidence": 1.0
}
```

#### 跑评测

```http
POST /api/evaluation/runs
```

输入：

```json
{
  "episode_id": "ep_063",
  "pipeline_version": "doubao_multimodal_v2",
  "candidate_source": "db_highlights",
  "iou_threshold": 0.3
}
```

输出：

```json
{
  "run_id": "eval_ep_063_20260604",
  "precision": 0.82,
  "recall": 0.76,
  "f1": 0.79,
  "type_accuracy": 0.68,
  "true_positive_count": 13,
  "false_positive_count": 3,
  "false_negative_count": 4,
  "items": [
    {
      "gold_label_id": 1,
      "pred_highlight_id": 12,
      "match_type": "tp",
      "iou": 0.55,
      "type_match": true
    }
  ]
}
```

### 核心函数 IO

```python
def time_iou(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    """返回两个时间段的 IoU。"""

def match_highlights(
    gold: list[HighlightGoldLabel],
    pred: list[Highlight],
    iou_threshold: float = 0.3,
) -> HighlightMatchResult:
    """贪心匹配 gold 和 pred，输出 TP/FP/FN 明细。"""

def compute_metrics(matches: HighlightMatchResult) -> HighlightMetrics:
    """输出 precision/recall/f1/type_accuracy。"""
```

### 数据流

```text
运营后台打开某集
  -> 拉取视频、高光、gold labels
  -> 人工拖时间轴新增/修正 gold label
  -> POST /api/evaluation/gold-labels
  -> 点击“运行评测”
  -> 后端读取 gold labels + highlights
  -> metrics.py 做时间 IoU 匹配
  -> 写 highlight_eval_runs
  -> 前端展示分数、误判列表、漏判列表
```

### 答辩展示指标

至少准备：

- 每部主展示剧 1 集 gold set
- 每集 8-15 个人工标签
- 输出一张表：precision / recall / f1 / type_accuracy
- 展示 2 个误判原因：字幕缺失、镜头切点不准、模型把铺垫当高光等

## 6. 人工运营/审核后台

### 目标功能

提供一个轻量后台，能做：

1. 高光点编辑：新增、修改、删除、调整时间、改互动类型。
2. 分支配置：编辑 fork、branch、分支视频 URL、下一分支。
3. AI 续写审核：查看用户生成内容，标记通过/隐藏/精选。
4. 弹幕举报处理：查看举报原因，隐藏弹幕。
5. 评测 dashboard：展示 gold set 和评测结果。

### 前端后台入口

建议先放 Flutter 内部隐藏路由：

```text
/admin
/admin/episodes/:episodeId/highlights
/admin/episodes/:episodeId/branches
/admin/reviews
/admin/evaluation
```

Flutter 路由：

```dart
r.child('/admin', child: (_) => const AdminPage());
```

### 后端 API

```http
GET    /api/admin/episodes
GET    /api/admin/highlights?episode_id=ep_063
POST   /api/admin/highlights
PUT    /api/admin/highlights/{highlight_id}
DELETE /api/admin/highlights/{highlight_id}

GET    /api/admin/branches/forks?episode_id=ep_063
POST   /api/admin/branches/forks
PUT    /api/admin/branches/forks/{fork_id}
DELETE /api/admin/branches/forks/{fork_id}
POST   /api/admin/branches
PUT    /api/admin/branches/{branch_id}
DELETE /api/admin/branches/{branch_id}

GET    /api/admin/reviews?status=pending&type=story
POST   /api/admin/reviews/{review_id}/approve
POST   /api/admin/reviews/{review_id}/reject
POST   /api/admin/danmaku/{danmaku_id}/hide
```

### Review 数据模型

```python
class ContentReviewItem(Base):
    __tablename__ = "content_review_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_type: Mapped[str] = mapped_column(String(32), index=True)  # danmaku/story/aigc_video
    item_id: Mapped[str] = mapped_column(String(128), index=True)
    episode_id: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    text: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(32), default="pending", index=True)
    risk_score: Mapped[float] = mapped_column(Float, default=0.0)
    reason: Mapped[str] = mapped_column(Text, default="")
    reviewer_id: Mapped[str] = mapped_column(String(64), default="")
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

### 核心函数 IO

```python
class AdminService:
    async def upsert_highlight(self, payload: HighlightAdminIn, admin: CurrentUser) -> HighlightOut:
        """新增或修改高光点，同时写 audit log。"""

    async def upsert_branch_fork(self, payload: BranchForkAdminIn, admin: CurrentUser) -> ForkOut:
        """维护分支点。"""

    async def review_item(self, review_id: int, decision: ReviewDecisionIn, admin: CurrentUser) -> ReviewItemOut:
        """审核内容，通过/拒绝/隐藏，并同步更新源对象状态。"""
```

Flutter 后台 controller：

```dart
class AdminController extends ChangeNotifier {
  Future<void> loadEpisode(String episodeId);
  Future<void> saveHighlight(HighlightDraft draft);
  Future<void> deleteHighlight(int highlightId);
  Future<void> saveFork(BranchForkDraft draft);
  Future<void> approveReview(int reviewId);
  Future<void> rejectReview(int reviewId, String reason);
}
```

### 数据流

```text
AdminPage 选择剧集
  -> AdminApiClient.getHighlights()
  -> HighlightEditor 时间轴拖拽
  -> saveHighlight()
  -> POST/PUT /api/admin/highlights
  -> DB 更新 highlights
  -> Player 重新拉取高光后生效
```

## 7. 生产级安全和治理

### 目标功能

Demo 阶段可以裸跑，但生产说明需要有完整安全设计：

- 用户登录和 token 鉴权
- 管理员权限
- API 限流
- 敏感词/内容审核
- 模型调用成本统计
- 审计日志
- API Key 不进入代码仓库

### 登录鉴权

新增 `users` 和 `device_sessions`：

```python
class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(64), default="")
    role: Mapped[str] = mapped_column(String(24), default="viewer")  # viewer/admin
    status: Mapped[str] = mapped_column(String(24), default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

class DeviceSession(Base):
    __tablename__ = "device_sessions"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(128), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(128))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

API：

```http
POST /api/auth/anonymous-login
POST /api/auth/refresh
GET  /api/auth/me
POST /api/auth/logout
```

登录输入：

```json
{
  "device_id": "macos_xxx",
  "display_name": "游客1234"
}
```

输出：

```json
{
  "access_token": "jwt...",
  "refresh_token": "opaque...",
  "user": {
    "id": "u_xxx",
    "display_name": "游客1234",
    "role": "viewer"
  }
}
```

后端依赖函数：

```python
async def get_current_user(request: Request, db: AsyncSession = Depends(get_db)) -> CurrentUser:
    """解析 Authorization Bearer token，返回当前用户。"""

def require_admin(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
    """校验 admin 权限。"""
```

Flutter：

```dart
class AuthSession extends ChangeNotifier {
  UserProfile? user;
  String? accessToken;
  String? refreshToken;

  Future<void> anonymousLogin();
  Future<void> refresh();
  Future<void> logout();
}
```

`ApiClient` 增加拦截器：

```dart
dio.interceptors.add(QueuedInterceptorsWrapper(
  onRequest: (options, handler) {
    options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    handler.next(options);
  },
  onError: (error, handler) async {
    if (error.response?.statusCode == 401) {
      await session.refresh();
      return handler.resolve(await dio.fetch(error.requestOptions));
    }
    handler.next(error);
  },
));
```

### API 限流

限流维度：

- `user_id`
- `ip`
- `endpoint_group`
- `model_provider`

新增 `rate_limit_buckets`：

```python
class RateLimitBucket(Base):
    __tablename__ = "rate_limit_buckets"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    route_group: Mapped[str] = mapped_column(String(64), index=True)
    window_start: Mapped[datetime] = mapped_column(DateTime)
    count: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
```

函数：

```python
async def check_rate_limit(
    user: CurrentUser,
    route_group: str,
    limit: int,
    window_seconds: int,
) -> None:
    """超限抛 HTTP 429。"""
```

### 内容审核

审核对象：

- 弹幕文本
- AI 续写用户输入
- AI 续写模型输出
- AIGC 视频 prompt
- 评论

函数：

```python
class ModerationService:
    async def check_text(self, text: str, scene: str, user_id: str) -> ModerationResult:
        """返回 allow/block/review 和 risk_score。"""

    async def create_review_if_needed(
        self,
        result: ModerationResult,
        item_type: str,
        item_id: str,
        episode_id: str,
        user_id: str,
        text: str,
    ) -> ContentReviewItem | None:
        """高风险入审核队列。"""
```

输出：

```json
{
  "decision": "review",
  "risk_score": 0.73,
  "reasons": ["敏感词", "人身攻击"],
  "masked_text": "..."
}
```

### 模型调用成本统计

新增 `model_call_logs`：

```python
class ModelCallLog(Base):
    __tablename__ = "model_call_logs"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32))
    model: Mapped[str] = mapped_column(String(128))
    scene: Mapped[str] = mapped_column(String(64))  # story_chat/highlight/aigc_video/moderation
    user_id: Mapped[str] = mapped_column(String(64), default="system")
    episode_id: Mapped[str] = mapped_column(String(64), default="")
    prompt_tokens: Mapped[int] = mapped_column(Integer, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cost_cents: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(32), default="ok")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

包装函数：

```python
async def tracked_chat_completion(
    messages: list[dict],
    *,
    scene: str,
    user_id: str,
    episode_id: str,
    temperature: float,
) -> str:
    """替代直接 chat_completion，统一记录耗时、模型、token 和失败。"""
```

## 8. 多端/多用户持久一致性

### 目标功能

同一个用户在不同设备上能同步喜欢、进度、AI 续写历史；多个用户同时观看时互动事件一致；AI story thread 进入数据库，不再只保存在 JSON 文件。

### Story Thread 入库

新增：

```python
class StoryThreadModel(Base):
    __tablename__ = "story_threads"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    fork_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ts_in_video: Mapped[float] = mapped_column(Float, default=0.0)
    style_code: Mapped[str] = mapped_column(String(64), default="cinematic_literary")
    title: Mapped[str] = mapped_column(String(256), default="")
    branch_path: Mapped[list[str]] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(32), default="visible")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class StoryTurnModel(Base):
    __tablename__ = "story_turns"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    thread_id: Mapped[str] = mapped_column(ForeignKey("story_threads.id"), index=True)
    role: Mapped[str] = mapped_column(String(32))
    parent_turn_id: Mapped[str | None] = mapped_column(String(96), nullable=True)
    selected_choice_id: Mapped[str | None] = mapped_column(String(96), nullable=True)
    text: Mapped[str] = mapped_column(Text)
    choices: Mapped[list[dict]] = mapped_column(JSON, default=list)
    evidence_event_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(32), default="visible")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

替换当前 repository：

```python
class StoryChatDbRepository:
    async def save_thread(self, thread: StoryThreadOut) -> StoryThreadOut:
        """upsert thread 和 turns 到 DB。"""

    async def get_thread(self, thread_id: str, user: CurrentUser | None = None) -> StoryThreadOut | None:
        """从 DB 读取 thread。"""

    async def list_user_threads(self, user_id: str, limit: int = 50) -> list[StoryThreadOut]:
        """个人中心展示历史 AI 续写。"""
```

新增 API：

```http
GET /api/story-chat/users/{user_id}/threads
```

输出：

```json
[
  {
    "thread_id": "thread_ep_063_xxx",
    "episode_id": "ep_063",
    "title": "北派寻宝笔记 第1集",
    "turn_count": 6,
    "last_text": "他抬头望向墓门...",
    "updated_at": "2026-06-04T..."
  }
]
```

### WebSocket 多实例一致性

当前单进程 `ws_manager` 可用，多实例部署时要加 Redis Pub/Sub：

```python
class RealtimeBus:
    async def publish(self, room: str, message: dict) -> None:
        """发布互动事件到 Redis。"""

    async def subscribe(self, room: str, handler: Callable[[dict], Awaitable[None]]) -> None:
        """订阅 Redis 并转发给本实例 WebSocket 客户端。"""
```

数据流：

```text
用户 A 点击“爽”
  -> POST /api/interactions(client_event_id)
  -> InteractionRepository 幂等写入 DB
  -> RealtimeBus.publish(episode_id, event)
  -> 所有后端实例订阅到 event
  -> 各自 ws_manager.broadcast(room)
  -> 用户 B/C/D 看到人数和特效变化
```

### 幂等性

已经有 `client_event_id`，需要扩大使用：

- 互动事件：`client_event_id`
- AI 生成：`request_id`
- AIGC 任务：`idempotency_key`
- 点赞/收藏：`user_id + episode_id + action` 唯一

Flutter：

```dart
String createRequestId(String scene) {
  return '${UserSession.userId}_${scene}_${DateTime.now().microsecondsSinceEpoch}';
}
```

## 9. 自动化端到端测试

### 目标功能

覆盖三类风险：

1. 播放器 UI 主流程不坏。
2. WebSocket 多用户互动一致。
3. AI 生成可回归，失败时有兜底。

### 后端测试目录

```text
backend/tests/
  conftest.py
  test_story_chat.py
  test_interactions_ws.py
  test_aigc_video.py
  test_evaluation_metrics.py
  fixtures/
    episodes.json
    highlights_ep_063.json
    story_chat_response.json
```

pytest 示例：

```python
async def test_story_chat_appends_turns(client, fake_ai_provider):
    res = await client.post("/api/story-chat/threads", json={
        "episode_id": "ep_063",
        "user_id": "u_test",
        "ts_in_video": 10,
        "context_hint": "主角出山",
    })
    thread = res.json()
    assert len(thread["turns"]) == 2

    res = await client.post(f"/api/story-chat/threads/{thread['thread_id']}/choose", json={
        "choice_label": "立刻反杀"
    })
    assert len(res.json()["thread"]["turns"]) == 4
```

WebSocket 多用户测试：

```python
async def test_ws_broadcasts_interaction(two_ws_clients, client):
    ws_a, ws_b = two_ws_clients
    await client.post("/api/interactions", json={
        "episode_id": "ep_063",
        "user_id": "u_a",
        "action": "爽",
        "ts_in_video": 32,
        "client_event_id": "evt_1",
    })
    message = await ws_b.receive_json()
    assert message["action"] == "爽"
```

### Flutter integration_test

```text
flutter_app/integration_test/
  player_interaction_flow_test.dart
  ai_story_chat_flow_test.dart
  admin_highlight_editor_test.dart
```

测试流程：

```dart
testWidgets('player can trigger AI story and keep history', (tester) async {
  await app.main();
  await tester.pumpAndSettle();
  await tester.tap(find.text('北派寻宝笔记'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('AI 剧情续写'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('生成续写'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
  expect(find.textContaining('续写对话'), findsOneWidget);
});
```

### AI 生成回归测试

原则：测试不直接依赖真实 Doubao。加 `FakeAiProvider`：

```python
class FakeAiProvider:
    async def chat_completion(self, messages: list[dict], temperature: float) -> str:
        return '{"text":"测试续写","choices":[{"label":"继续反转"},{"label":"情感升温"},{"label":"悬念升级"}]}'
```

在测试环境通过环境变量切换：

```text
AI_PROVIDER=fake
AIGC_VIDEO_PROVIDER=mock
```

### CI 命令

```bash
cd backend
.venv/bin/python -m pytest tests

cd flutter_app
flutter analyze --no-pub
flutter test
flutter test integration_test
```

## 10. 音效资源和完整互动资产包

### 目标功能

把“爽/笑/燃/哭/反杀/撒糖/完结”等互动做成可配置资产，而不是写死在 painter 或 UI 里。每个互动类型绑定：

- 图标
- Lottie/SVG/CustomPainter 动效
- 音效文件
- haptic 强度
- 颜色
- 展示时长
- 触发规则

### 资源目录

```text
flutter_app/assets/
  effects/
    manifest.json
    icons/
      shuang.svg
      laugh.svg
      burn.svg
    lottie/
      shuang_burst.json
      laugh_pop.json
    sounds/
      shuang_hit.mp3
      laugh_pop.mp3
      burn_whoosh.mp3
```

`pubspec.yaml`：

```yaml
flutter:
  assets:
    - assets/effects/manifest.json
    - assets/effects/icons/
    - assets/effects/lottie/
    - assets/effects/sounds/
```

### Manifest 结构

```json
{
  "version": "2026.06.04",
  "effects": [
    {
      "code": "shuang",
      "label": "爽",
      "actions": ["爽", "打脸爽点", "反杀"],
      "icon": "assets/effects/icons/shuang.svg",
      "animation": {
        "type": "custom_painter",
        "preset": "ignition",
        "duration_ms": 900
      },
      "sound": {
        "url": "assets/effects/sounds/shuang_hit.mp3",
        "volume": 0.8
      },
      "haptic": "heavy",
      "colors": ["#FF4F72", "#FFC857"]
    }
  ]
}
```

### 后端资产 API

可先前端本地 manifest，后续接后端：

```http
GET /api/assets/effects
```

输出：

```json
{
  "version": "2026.06.04",
  "effects": [...]
}
```

新增表：

```python
class InteractionEffectAsset(Base):
    __tablename__ = "interaction_effect_assets"

    code: Mapped[str] = mapped_column(String(64), primary_key=True)
    label: Mapped[str] = mapped_column(String(32))
    actions: Mapped[list[str]] = mapped_column(JSON, default=list)
    icon_url: Mapped[str] = mapped_column(String(512), default="")
    animation_json: Mapped[dict] = mapped_column(JSON, default=dict)
    sound_url: Mapped[str] = mapped_column(String(512), default="")
    haptic: Mapped[str] = mapped_column(String(32), default="light")
    colors: Mapped[list[str]] = mapped_column(JSON, default=list)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
```

### Flutter 核心类

```dart
class InteractionEffectAsset {
  final String code;
  final String label;
  final List<String> actions;
  final String icon;
  final EffectAnimationSpec animation;
  final EffectSoundSpec? sound;
  final String haptic;
  final List<Color> colors;
}

class EffectAssetRegistry extends ChangeNotifier {
  final ApiClient _api;
  Map<String, InteractionEffectAsset> byAction = {};

  Future<void> load();
  InteractionEffectAsset resolve(String action);
}

class InteractionSoundController {
  Future<void> preload(List<InteractionEffectAsset> assets);
  Future<void> play(String action);
  Future<void> setEnabled(bool enabled);
}
```

播放器数据流：

```text
InteractionController 收到本地/远端互动 action
  -> EffectAssetRegistry.resolve(action)
  -> HighlightEffectOverlay 使用 animation preset 和 colors
  -> InteractionSoundController.play(action)
  -> HapticFeedback 根据 haptic 执行
  -> InteractionEvent 写 asset_code，便于统计哪个资产被触发
```

## 建议实施顺序

### 第一阶段：答辩增强，2-3 天

1. 高光评测 gold set + metrics。
2. 分支点补充和后台最小编辑能力。
3. 音效 manifest + 3 个核心音效。

### 第二阶段：创新展示，3-5 天

1. AIGC 视频 mock provider + 插片播放链路。
2. AIGC 真实 provider 适配器。
3. AI 续写内容审核和精选。

### 第三阶段：生产化说明，3-5 天

1. 登录鉴权、管理员权限。
2. rate limit、moderation、model call logs。
3. story thread 入库、Redis 实时广播。
4. 自动化 E2E 和 CI。

## 最小可交付清单

如果时间紧，建议只做下面这些就能显著增强答辩：

1. `evaluation`：实现 gold label + run metrics，拿出准确率表。
2. `admin`：实现高光编辑和分支编辑，不必做完整后台权限。
3. `aigc_video`：实现 mock provider + 插片播放，不强求实时生成。
4. `effects`：实现 manifest + 3 个音效，增强观感。
5. `tests`：实现 story chat append、interaction post、WebSocket broadcast 三个后端测试。

