# AI 剧情识别与分支续写质量优化方案

调研日期：2026-06-01

## 1. 背景问题

当前项目已经有两块 AI 能力：

- 离线高光识别：`ai_pipeline/highlight_detector.py` 将视频切成 8 秒窗口，每个窗口取 1 帧和同窗口字幕，调用 Doubao 多模态模型判断是否是剧情高光。
- 在线剧情续写：`backend/app/services/ai_service.py` 根据前端传入的 `context + choice` 生成一段续写和 3 个后续选项。

现在感觉“AI 识别剧情不准确，后面续写也不行”，本质原因不是续写模型单点质量问题，而是上游剧情理解给续写提供的事实太薄、太不稳定。

当前主要风险：

1. **证据太少**：每个 8 秒窗口只给模型 1 帧，且取桶内首帧，不一定是冲突点、反转点或人物表情关键帧。
2. **时间关系断裂**：短剧爽点通常依赖“上一幕压迫 - 当前反击 - 下一幕反转”，单窗口判断容易误判。
3. **字幕噪声未校验**：Whisper 输出没有置信度、说话人、原字幕校对和 OCR 补充，台词一错，剧情判断会被带偏。
4. **没有剧情记忆**：高光识别和续写都没有稳定读取“人物关系、前情摘要、上一集事件、当前分支路径”。
5. **单阶段 LLM 判断**：现在让模型一次性完成“理解剧情 + 判断高光 + 生成描述”，缺少结构化事实抽取和校验。
6. **续写使用的 context 太弱**：前端目前主要传 `episode.title + activeHighlight.summary`，信息量不足，导致续写经常泛化成模板爽文。

## 2. 外部调研结论

### 2.1 长视频理解的难点

长视频/影视剧情理解比普通图文理解难，因为模型需要同时处理视觉、台词、时间顺序和人物关系。

调研到的长视频理解 benchmark 和论文都强调：视频越长、线索跨度越大，现有模型表现会明显下降。LvBench 论文指出，长视频评测需要覆盖 70 秒到 4 小时的视频，并结合视频帧和字幕评估多种感知与认知能力，同时观察到现有方法随视频和线索长度增加而明显变差。

对本项目的启发：不能把一集短剧当成一堆互不相关的 8 秒窗口，要建立“时间线记忆”和“人物关系记忆”。

来源：

- [LvBench: A Benchmark for Long-form Video Understanding](https://arxiv.org/abs/2312.04817)

### 2.2 Video-RAG 是低成本可落地方案

Video-RAG 类方案的核心不是直接把整集视频塞给模型，而是先把视频变成可检索的结构化证据：字幕、关键帧描述、OCR、物体/人物、音频事件、时间戳，再按问题检索相关片段。

Video-RAG 论文提出使用视觉对齐的辅助文本来帮助长视频理解，包含音频、OCR、物体检测等信息，并作为 plug-and-play 的方式接入现有 LVLM。另一个 VideoRAG 长上下文论文提出双通道设计：图结构文本 grounding + 多模态上下文编码。

对本项目的启发：先把短剧离线处理成“剧情知识库”，在线续写时只检索当前时刻相关证据，而不是依赖前端临时拼一句摘要。

来源：

- [Video-RAG: Visually-aligned Retrieval-Augmented Long Video Comprehension](https://huggingface.co/papers/2411.13093)
- [VideoRAG: Retrieval-Augmented Generation with Extreme Long-Context Videos](https://arxiv.org/abs/2502.01549)

### 2.3 结构化记忆比直接问模型更稳

VideoAgent 采用 Temporal Memory 和 Object Memory，把长视频转成结构化记忆，再由 LLM 调用工具查询记忆。ViG-RAG 使用带时间戳和置信度的时序知识图谱，把实体、关系、时间和可信度组织起来。

对本项目的启发：短剧剧情可以抽成轻量图谱，不需要一开始做复杂知识图谱系统，但至少要保存：

- 谁对谁做了什么
- 这件事发生在第几集、几秒到几秒
- 证据来自台词、画面、OCR 还是弹幕
- 这个事实的置信度
- 这个事件在剧情中的作用：压迫、反击、揭露、反转、和解、钩子

来源：

- [VideoAgent: A Memory-augmented Multimodal Agent for Video Understanding](https://www.sciencestack.ai/paper/2403.11481v2)
- [ViG-RAG: Video-aware Graph Retrieval-Augmented Generation](https://ojs.aaai.org/index.php/AAAI/article/download/36963/40925)

### 2.4 影视剧情需要“脚本级”结构

OmniScript 提出的 Video-to-Script 任务，目标是从长影视视频生成按场景组织、带时间 grounding 的脚本，包括角色动作、对话、表情和音频线索。

对本项目的启发：高光识别不应只输出 `type/description`，应该先输出“脚本事件”，再从脚本事件里筛选互动点和分支点。

来源：

- [OmniScript: Towards Audio-Visual Script Generation for Long-Form Cinematic Video](https://arcomniscript.github.io/)

### 2.5 输出格式必须 schema 化

OpenAI Structured Outputs 文档明确区分 JSON mode 和 Structured Outputs：JSON mode 只保证 JSON 有效，不保证符合具体 schema；Structured Outputs 可以约束模型匹配 JSON Schema。同时文档也提醒，结构化输出仍可能出现语义错误，需要拆任务、给示例、做 eval。

对本项目的启发：即使用 Doubao，也应该把输出变成严格 Pydantic schema，应用侧做校验、重试、降级，而不是用正则抽 JSON 后直接信任。

来源：

- [OpenAI Structured Outputs 官方文档](https://developers.openai.com/api/docs/guides/structured-outputs)
- [火山方舟 Chat Completions API](https://www.volcengine.com/docs/82379/1494384)

### 2.6 ASR 和场景切分是底座

Whisper 是 robust ASR 的常用开源方案，但字幕仍然需要校验和对齐。PySceneDetect 的内容感知检测可用于镜头切分，它基于相邻帧颜色/亮度变化检测 cut。

对本项目的启发：字幕、镜头、音频峰值和画面帧要互相校验，不能只依赖单一信号。

来源：

- [OpenAI Whisper](https://openai.com/research/whisper)
- [PySceneDetect Scene Detection Algorithms](https://www.scenedetect.com/docs/api/detectors.html)

## 3. 目标方案：从“高光识别”升级为“剧情证据链”

推荐把现有 pipeline 改成三层：

```text
离线层：视频 -> 剧情证据库
  字幕 ASR / OCR / 镜头切分 / 多帧描述 / 音频峰值 / 弹幕热度
  -> PlotEvent[]
  -> StoryMemory

服务层：剧情上下文构造
  episode_id + current_time + fork_id + choice + branch_history
  -> 检索相关 PlotEvent / 角色卡 / 前情摘要 / 当前冲突
  -> BranchGenerationContext

生成层：分支续写
  BranchGenerationContext
  -> 结构化续写 JSON
  -> 保存 story_id / choices / evidence
```

核心思想：续写只使用被证据链验证过的剧情事实，不直接使用模型临时猜出来的摘要。

## 4. 数据结构建议

### 4.1 PlotEvent

用于替代当前 `Highlight.description` 这种单薄摘要。

```python
class PlotEvent(BaseModel):
    episode_id: str
    scene_id: str
    ts_start: float
    ts_end: float
    characters: list[str]
    event_type: Literal[
        "压迫", "反击", "身份揭露", "打脸", "反转",
        "和解", "暧昧", "悬念", "搞笑", "铺垫"
    ]
    summary: str
    dialogue_evidence: list[str]
    visual_evidence: list[str]
    narrative_role: Literal[
        "铺垫", "冲突升级", "真相揭露", "情绪释放", "关系变化", "剧尾钩子"
    ]
    confidence: float
    source_signals: list[str]
```

### 4.2 BranchGenerationContext

在线续写时不要只传 `context: str`，而是传结构化上下文。

```python
class BranchGenerationContext(BaseModel):
    episode_id: str
    current_time: float
    drama_title: str
    episode_title: str
    role_cards: list[RoleCard]
    previous_summary: str
    current_scene_events: list[PlotEvent]
    recent_events: list[PlotEvent]
    selected_choice: str | None
    branch_history: list[str]
    style: str = "短剧爽感、节奏快、强反转"
```

### 4.3 BranchStoryOut

建议从纯文本升级为可追踪对象。

```python
class BranchStoryOut(BaseModel):
    story_id: str
    text: str
    choices: list[BranchChoiceOut]
    evidence_event_ids: list[str]
    confidence: float
    warnings: list[str] = []
```

## 5. Pipeline 改造方案

### 5.1 当前 pipeline

```text
extract_frames.py
  -> scene 中心帧 + 4s 均匀帧

whisper_asr.py
  -> subtitles segments

highlight_detector.py
  -> 8s 窗口
  -> 1 帧 + 字幕
  -> Doubao 判断高光
  -> data/highlights/<episode>.json
```

### 5.2 建议 pipeline

```text
video.mp4
  -> scene_detect.py
  -> whisper_asr.py
  -> subtitle_cleaner.py
  -> frame_sampler.py
  -> visual_captioner.py
  -> plot_event_extractor.py
  -> plot_event_ranker.py
  -> story_memory_builder.py
  -> data/narrative_events/<episode>.json
  -> data/story_memory/<drama>.json
```

### 5.3 关键函数输入输出

```python
def build_plot_windows(
    frames: list[Frame],
    subtitles: list[SubtitleSegment],
    scenes: list[Scene],
    window_size: float = 8.0,
    stride: float = 4.0,
) -> list[PlotWindow]:
    """输出带前后文的重叠窗口，而不是互斥窗口。"""
```

```python
async def extract_plot_events(
    windows: list[PlotWindow],
    role_cards: list[RoleCard],
) -> list[PlotEvent]:
    """只做事实抽取，不直接决定高光。"""
```

```python
def rank_branch_candidates(
    events: list[PlotEvent],
    danmaku_heat: list[HeatPoint] | None = None,
) -> list[BranchCandidate]:
    """基于冲突强度、反转潜力、证据置信度筛选可分支点。"""
```

```python
async def build_generation_context(
    episode_id: str,
    current_time: float,
    selected_choice: str | None,
    branch_history: list[str],
    db: AsyncSession,
) -> BranchGenerationContext:
    """在线生成前，从剧情记忆库检索上下文。"""
```

## 6. 算法策略

### 6.1 多帧替代单帧

每个窗口建议传 3 到 5 帧：

- 窗口开始帧：看冲突起点
- 中心帧：看当前状态
- 结束帧：看情绪/动作结果
- 镜头切点前后帧：看转场和反应

如果成本敏感，可以先用本地规则选关键帧，再只把 Top 3 发给多模态模型。

### 6.2 重叠窗口替代固定桶

当前 8 秒窗口互斥，容易把关键剧情切断。建议：

- `window_size = 10s`
- `stride = 5s`
- 对同一事件做 NMS/合并
- 事件边界用字幕时间戳和镜头切点微调

### 6.3 先抽事实，再评高光

不要让模型一次性输出高光结论。拆成两步：

1. 事实抽取：发生了什么，谁和谁，证据是什么，置信度多少。
2. 高光/分支评分：这个事实是否适合互动，为什么，应该触发什么互动。

好处：

- 续写可以引用事实事件，不依赖高光摘要。
- 错误容易定位，是 ASR 错、视觉错、还是评分错。
- 可以做人工抽检和回归测试。

### 6.4 证据投票

一个剧情事件至少需要两类证据中的一类强证据：

- 台词证据：明确说出身份、威胁、道歉、反击等。
- 画面证据：跪下、打斗、哭泣、拥抱、多人围堵等。
- 弹幕证据：大量“爽”“反转”“太奶奶”等热点词。
- 音频证据：尖叫、掌声、音乐爆点、突然静音。

示例规则：

```python
confidence = (
    0.35 * dialogue_score +
    0.30 * visual_score +
    0.15 * temporal_consistency_score +
    0.10 * audio_score +
    0.10 * danmaku_score
)
```

低于 `0.65` 的事件不进入续写上下文；低于 `0.75` 的事件不自动生成分支点。

### 6.5 角色卡和关系图

短剧续写很容易跳戏，尤其是人物关系错。建议每部剧维护轻量角色卡：

```json
{
  "drama_id": "shibasuitainainai",
  "characters": [
    {
      "name": "太奶奶",
      "aliases": ["老祖宗", "她"],
      "traits": ["辈分高", "护短", "反套路"],
      "relationships": [
        {"target": "家族小辈", "relation": "长辈/保护者"}
      ]
    }
  ]
}
```

角色卡可以先人工写 5 到 10 个核心角色，后续再用 AI 从字幕里补充。

## 7. 后端目录建议

```text
backend/app/
  domains/
    narrative/
      schemas.py
      repository.py
      context_builder.py
      memory_retriever.py
      prompt_builder.py
      quality_guard.py
      service.py
  api/
    narrative.py
    branch_generation.py
  services/
    llm_client.py
```

职责：

- `narrative/schemas.py`：`PlotEvent`, `RoleCard`, `BranchGenerationContext`
- `context_builder.py`：从 episode、highlight、subtitles、branch history 构造上下文
- `memory_retriever.py`：按 `episode_id + current_time + choice` 检索剧情证据
- `quality_guard.py`：校验 AI 输出是否符合 schema、是否引用了真实证据
- `branch_generation.py`：提供新的 `POST /api/branches/generate`

## 8. 数据目录建议

```text
data/
  narrative_events/
    ep_063.json
    sbtnn_001.json
  story_memory/
    beipaixunbao.json
    shibasuitainainai.json
  role_cards/
    beipaixunbao.json
    tianxiadyi.json
    shibasuitainainai.json
  eval_sets/
    plot_event_gold.json
    branch_generation_gold.json
```

## 9. 续写接口建议

当前：

```http
POST /api/interactions/branch
{
  "episode_id": "sbtnn_001",
  "context": "十八岁太奶奶\n家族众人质疑她身份",
  "choice": "当场亮辈分镇住众人"
}
```

建议新增：

```http
POST /api/branches/generate
{
  "episode_id": "sbtnn_001",
  "user_id": "anon",
  "ts_in_video": 52.0,
  "fork_id": 3,
  "selected_choice": "当场亮辈分镇住众人",
  "parent_story_id": null,
  "style": "爽点密集"
}
```

后端自己查上下文，不再依赖前端手写 `context`。

返回：

```json
{
  "story_id": "story_sbtnn_001_52_001",
  "text": "她没有急着解释，只是抬手亮出祖传信物...",
  "choices": [
    {
      "choice_id": "c1",
      "label": "重整家规",
      "intent": "权力反转",
      "preview": "当众立规矩，镇住全场"
    }
  ],
  "evidence_event_ids": ["sbtnn_001_004"],
  "confidence": 0.82,
  "warnings": []
}
```

## 10. 评测闭环

要解决“不准确”，必须建立小型 gold set，否则每次改 prompt 都是凭感觉。

建议先做 30 个片段：

- 每部剧 10 个片段
- 每个片段 20 到 40 秒
- 人工标注：角色、事件、剧情类型、是否适合分支、正确续写方向

指标：

| 指标 | 说明 | 目标 |
|---|---|---|
| 事件召回 | 关键剧情是否被识别 | > 85% |
| 时间命中 | 识别时间是否落在人工标注 ±2s | > 75% |
| 类型准确率 | 身份反转/打脸/悬念等分类是否正确 | > 80% |
| 证据覆盖率 | 输出是否带真实台词/画面证据 | > 90% |
| 续写一致性 | 是否符合人物关系和前情 | > 85% |
| 分支可玩性 | 三个选项是否有差异 | > 80% |

每次改 pipeline 后跑一次：

```bash
python scripts/eval_plot_events.py --gold data/eval_sets/plot_event_gold.json
python scripts/eval_branch_generation.py --gold data/eval_sets/branch_generation_gold.json
```

## 11. 分阶段落地路线

### Phase 1：低成本修正，1 到 2 天

目标：不大改架构，先明显提升准确率。

1. `highlight_detector.py` 每窗口改为 3 帧输入。
2. `build_windows` 改成 10 秒窗口、5 秒 stride。
3. 输出增加 `evidence`, `confidence_reason`, `characters`。
4. 低置信度高光不进入续写。
5. `/api/interactions/branch` 使用 `episode_id` 查询本集高光和字幕窗口，构造后端上下文。

### Phase 2：剧情事件层，3 到 5 天

目标：把“高光描述”升级为“剧情事件”。

1. 新增 `data/narrative_events/<episode>.json`。
2. 新增 `plot_event_extractor.py`。
3. 新增 `role_cards/<drama>.json`。
4. 新增 `context_builder.py`，续写只读 `PlotEvent + RoleCard`。
5. 前端继续用原 UI，接口兼容返回 `text + choices`。

### Phase 3：RAG 和评测闭环，5 到 7 天

目标：让生成质量可回归、可解释。

1. 建 `story_memory` 和 embeddings 索引。
2. 新增 `branch_generation` domain。
3. 生成结果落库，带 `story_id`。
4. 建 30 条 gold set。
5. 加 eval 脚本和质量报表。

## 12. 推荐优先级

如果只想快速解决“识别不准导致续写烂”，优先做这 5 件事：

1. **后端接管上下文构造**：前端不要再手拼 `context`。
2. **高光识别输出证据和置信度**：没有证据的高光不要用于续写。
3. **多帧 + 前后窗口**：解决单帧误判。
4. **剧情事件缓存**：先离线生成 `PlotEvent`，续写只基于事件。
5. **小型人工 gold set**：用 30 个片段建立评测基线。

这样改完后，AI 续写会从“凭一句摘要自由发挥”变成“根据当前剧情证据继续写”，质量会稳定很多。

