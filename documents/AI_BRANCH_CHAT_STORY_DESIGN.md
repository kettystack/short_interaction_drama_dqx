# 对话式 AI 剧情续写设计方案

调研日期：2026-06-01

## 1. 目标

当前 AI 剧情续写弹窗更像“一次性生成卡片”：用户选择分支后，新的续写会覆盖上一段 `generatedStory`，用户看不到完整对话历史，也无法像 AI 对话一样一轮轮推进。

目标改成：

1. **对话式剧情流**：每次用户选择分支后，AI 都追加一条新的剧情，不覆盖原来的内容。
2. **自动往下续**：用户点选项后，后端基于上一次故事、选择路径、剧情证据链自动续写下一轮。
3. **风格可控**：默认短剧爽感可保留，但增加“文艺电影感”“克制悬疑感”“古风章回感”等 style profile。
4. **可追踪**：每一轮都有 `turn_id/story_id/parent_turn_id/choice_id`，方便点赞、评论、回溯、重生成。
5. **可渐进落地**：先做文字聊天流，再考虑 AIGC 视频或分支视频挂接。

## 2. 市面调研

### 2.1 AI Dungeon：开放式冒险 + 记忆系统

AI Dungeon 的核心是“用户输入动作，AI 继续生成冒险”。App Store 介绍里强调它是 AI-native RPG/text-adventure，支持预设场景、自定义故事、多人游玩，并用 Story Cards / Memory Banks 存储上下文相关信息。

可借鉴点：

- 用户动作不是一次性表单，而是持续回合。
- 需要“记忆系统”区分长期设定和当前短期剧情。
- Story Cards / Memory 类机制适合保存角色、地点、关键物件、伏笔。

来源：

- [AI Dungeon App Store](https://apps.apple.com/us/app/ai-dungeon/id1491268416)
- [Latitude: AI Dungeon](https://content.latitude.io/)

### 2.2 Character.AI：角色人格 + Pinned Memories + 群聊

Character.AI 的优势不是剧情树，而是“角色人格”和“聊天沉浸”。其官方帮助中心介绍了 Pinned Memories，可把每个聊天中重要消息固定下来，让角色记住关键细节；Group Chat 支持多个人和多个 AI 角色同场对话。

可借鉴点：

- 每个角色需要人格、说话方式、关系卡。
- 用户可“钉住”重要剧情，防止长对话后遗忘。
- 剧情续写可以引入“旁白 + 角色台词”的多说话人结构，而不是一段旁白糊过去。

来源：

- [Character.AI Pinned Memories](https://support.character.ai/hc/en-us/articles/24327914463003-New-Feature-Pinned-Memories)
- [Character.AI Group Chat FAQ](https://support.character.ai/hc/en-us/articles/23957256282523-Group-Chat-FAQ)
- [Character.AI Greeting 文档](https://book.character.ai/character-book/character-attributes/greeting)

### 2.3 NovelAI：Memory / Author's Note / Lorebook / Redo Tree

NovelAI 更接近“AI 写作工具”。官方文档里有 Story Settings、Memory、Author's Note、Lorebook 等概念；FAQ 提到故事可导出，包括 Settings、Redo Tree、Memory、Author's Note、Lorebook entries 和自定义模块。

可借鉴点：

- `Memory`：每轮都要放入上下文的长期摘要。
- `Author's Note`：控制文风、节奏、视角。
- `Lorebook`：根据关键词激活角色/家族/物件设定。
- `Redo Tree`：同一轮可生成多个候选，不直接覆盖旧版本。

来源：

- [NovelAI Story Settings](https://docs.novelai.net/en/text/editor/storysettings)
- [NovelAI Lorebook](https://docs.novelai.net/en/text/lorebook)
- [NovelAI FAQ](https://docs.novelai.net/en/faq)

### 2.4 Episode：选择驱动的移动端互动故事

Episode 的官网定位是移动端互动故事，用户选择会决定故事路径。它不是 AI 生成，但它的选择卡、移动端节奏、分支体验值得借鉴。

可借鉴点：

- 选择按钮要短、明确、有情绪价值。
- 每次选择应该带来可感知差异，而不是三条同义选项。
- 移动端阅读最好是“气泡/段落流 + 选择卡”，不要每轮都弹一个新大弹窗。

来源：

- [Episode 官方网站](https://www.episodeinteractive.com/)

## 3. 产品形态建议

### 3.1 从弹窗卡片改成 Story Chat Sheet

当前形态：

```text
输入当前剧情
  -> 生成一段正文
  -> 下方 3 个选项
  -> 再点选项时覆盖原文
```

建议形态：

```text
AI 剧情续写 Sheet
  ├─ 剧情上下文提示卡
  ├─ 回合 1：AI 续写正文
  ├─ 用户选择：当场亮辈分
  ├─ 回合 2：AI 继续正文
  ├─ 用户选择：追查幕后黑手
  ├─ 回合 3：AI 继续正文
  └─ 底部：输入自由指令 / 继续生成 / 重写本轮
```

关键原则：

- 生成内容 append 到 `turns[]`，不再覆盖 `generatedStory`。
- 当前可选项只属于最后一个 AI turn。
- 点选项后立即插入一条 `user_choice` turn，再请求 AI 生成下一条 `assistant_story` turn。
- 每一轮可点赞、评论、重写、复制、收藏。

### 3.2 更文艺的默认风格

现在生成的问题是：用词像“爽文套路模板”，缺少画面感、节制和人物细节。

推荐提供 4 个 style profile：

```json
[
  {
    "code": "cinematic_literary",
    "name": "文艺电影感",
    "prompt": "画面感强，句子克制，少喊口号，多写动作、停顿、光线和人物微表情。保留短剧推进，但避免网络爽文腔。"
  },
  {
    "code": "suspense_noir",
    "name": "克制悬疑感",
    "prompt": "节奏压低，信息一点点露出，人物话里有话，结尾留下一个具体钩子。"
  },
  {
    "code": "short_drama_punchy",
    "name": "短剧高爽感",
    "prompt": "节奏快，冲突强，反转明确，适合短视频观看，但避免粗糙口水话。"
  },
  {
    "code": "classical_chapter",
    "name": "古风章回感",
    "prompt": "适合古装题材，语言有章回余味，但不写成文言文，台词自然。"
  }
]
```

文艺感 prompt 核心：

```text
不要只写“她反手打脸”“全场震惊”这类总结句。
每 2-3 句必须包含一个可被拍出来的动作或画面细节。
台词不超过全文 35%，但每句台词都要推动关系或信息。
结尾留一个具体动作钩子，而不是抽象悬念。
```

## 4. 推荐目录结构

### 4.1 后端

当前已有 `backend/app/domains/narrative` 和 `/api/branches/generate`，可以继续扩展，不要再堆到 `ai_service.py` 里。

```text
backend/app/
  api/
    story_chat.py                  # 新增：对话式剧情 API
    branch_generation.py           # 保留：单轮证据链续写

  domains/
    story_chat/
      schemas.py                   # StoryThread / StoryTurn / StoryChoice
      repository.py                # 读写对话历史
      context_builder.py           # branch history + narrative events -> prompt context
      prompt_builder.py            # style profile + history -> LLM messages
      service.py                   # append turn / continue / retry
      style_profiles.py            # 文风配置
      quality_guard.py             # JSON schema 校验、风格检查、降级

    narrative/
      schemas.py                   # 已有 PlotEvent / RoleCard
      repository.py                # 已有 data/narrative_events 读取
      memory_retriever.py          # 已有剧情证据检索
```

### 4.2 Flutter

```text
flutter_app/lib/features/player/
  controllers/
    story_chat_controller.dart       # 管理 turns、loading、选择路径
    interaction_controller.dart      # 保留互动点赞/弹幕/高光

  widgets/
    story_chat_sheet.dart            # 新的 AI 对话式剧情 Sheet
    story_turn_bubble.dart           # 旁白/用户选择/系统提示气泡
    story_choice_bar.dart            # 最后一轮的 3 个选项
    story_style_selector.dart        # 文风切换
```

### 4.3 数据目录

```text
data/
  story_styles/
    profiles.json
  narrative_events/
    sbtnn_001.json
  role_cards/
    shibasuitainainai.json
  story_memory/
    shibasuitainainai.json
```

## 5. 数据模型

### 5.1 StoryThread

```python
class StoryThread(BaseModel):
    thread_id: str
    episode_id: str
    user_id: str
    fork_id: int | None = None
    ts_in_video: float
    style_code: str = "cinematic_literary"
    title: str = ""
    turns: list[StoryTurn] = Field(default_factory=list)
    branch_path: list[str] = Field(default_factory=list)
```

### 5.2 StoryTurn

```python
class StoryTurn(BaseModel):
    turn_id: str
    thread_id: str
    role: Literal["system", "user_choice", "assistant_story"]
    parent_turn_id: str | None = None
    selected_choice_id: str | None = None
    text: str
    choices: list[StoryChoice] = Field(default_factory=list)
    evidence_event_ids: list[str] = Field(default_factory=list)
    created_at: datetime
```

### 5.3 StoryChoice

```python
class StoryChoice(BaseModel):
    choice_id: str
    label: str                 # 按钮文案，12字以内
    intent: str                # 例如：身份揭露 / 暗线调查 / 情感缓和
    preview: str               # 一句话预告
    tone: str = ""             # 爽 / 悬疑 / 温情 / 文艺
```

## 6. API 设计

### 6.1 创建或打开线程

```http
POST /api/story-chat/threads
```

输入：

```json
{
  "episode_id": "sbtnn_001",
  "user_id": "anon",
  "fork_id": 3,
  "ts_in_video": 52.0,
  "initial_choice": "当场亮辈分镇住众人",
  "style_code": "cinematic_literary"
}
```

输出：

```json
{
  "thread_id": "thread_sbtnn_001_52_xxx",
  "episode_id": "sbtnn_001",
  "style_code": "cinematic_literary",
  "turns": [
    {
      "turn_id": "turn_001",
      "role": "assistant_story",
      "text": "院子里忽然安静下来。她把那枚旧银扣放在桌上...",
      "choices": [
        {"choice_id": "c1", "label": "翻旧族谱", "intent": "身份揭露", "preview": "让辈分有证可查"}
      ]
    }
  ]
}
```

### 6.2 选择一个分支继续

```http
POST /api/story-chat/threads/{thread_id}/choose
```

输入：

```json
{
  "choice_id": "c1",
  "choice_label": "翻旧族谱"
}
```

输出：完整 thread，或只返回新追加的 turns。

```json
{
  "appended_turns": [
    {
      "role": "user_choice",
      "text": "翻旧族谱"
    },
    {
      "role": "assistant_story",
      "text": "族谱被取来时，纸页边缘已经发黄...",
      "choices": []
    }
  ]
}
```

### 6.3 自由输入继续

```http
POST /api/story-chat/threads/{thread_id}/message
```

输入：

```json
{
  "text": "让她不要马上公开身份，而是先观察谁最心虚"
}
```

适合做成聊天输入框。

## 7. 核心函数 IO

### 7.1 后端 service

```python
class StoryChatService:
    async def create_thread(self, payload: StoryThreadCreateIn) -> StoryThreadOut:
        thread = await repo.create_thread(payload)
        context = await build_story_chat_context(thread, payload.initial_choice)
        assistant_turn = await generate_next_turn(thread, context)
        await repo.append_turns(thread.thread_id, [assistant_turn])
        return await repo.get_thread(thread.thread_id)

    async def choose(self, thread_id: str, payload: StoryChoiceIn) -> StoryThreadDeltaOut:
        user_turn = make_user_choice_turn(thread_id, payload)
        context = await build_story_chat_context(thread_id, payload.choice_label)
        assistant_turn = await generate_next_turn(thread_id, context)
        await repo.append_turns(thread_id, [user_turn, assistant_turn])
        return StoryThreadDeltaOut(appended_turns=[user_turn, assistant_turn])
```

### 7.2 Prompt builder

```python
def build_story_chat_messages(
    thread: StoryThread,
    context: BranchGenerationContext,
    style: StoryStyleProfile,
) -> list[dict]:
    """把长期记忆、最近 turns、剧情证据、文风要求组装成 LLM messages。"""
```

### 7.3 Flutter controller

```dart
class StoryChatController extends ChangeNotifier {
  StoryThread? thread;
  bool isLoading = false;
  String? error;

  Future<void> open({
    required String episodeId,
    required double tsInVideo,
    int? forkId,
    String? initialChoice,
    String styleCode = 'cinematic_literary',
  });

  Future<void> choose(StoryChoice choice);

  Future<void> sendFreeText(String text);
}
```

## 8. 变量数据流

```text
PlayerPage
  episodeId / currentTime / pendingFork / selectedBranchOption
        |
        v
StoryChatController.open(...)
        |
        v
POST /api/story-chat/threads
        |
        v
StoryChatService.create_thread
        |
        v
NarrativeContextBuilder
  Episode + PlotEvent + RoleCard + previous_summary
        |
        v
StoryChatPromptBuilder
  style_profile + recent_turns + selected_choice + evidence
        |
        v
LLM structured JSON
        |
        v
QualityGuard
  choices=3 / evidence ids valid / style checks / fallback
        |
        v
Repository.append_turns
        |
        v
Flutter StoryChatSheet
  ListView 展示所有 turns，不覆盖旧剧情
```

## 9. Prompt 方案

### 9.1 文艺电影感 system prompt

```text
你是互动短剧的文学型编剧，负责把短剧分支写成可连续阅读的剧情对话流。

硬性要求：
- 只基于输入中的剧情证据链、角色卡和历史 turn 续写。
- 180 字以内。
- 句子有画面感，少用“全场震惊”“霸气反杀”这类总结词。
- 至少写 2 个可被拍出来的动作/表情/环境细节。
- 台词要短，每句台词必须推动关系或信息。
- 最后一行留下具体动作钩子。
- 输出严格 JSON。
```

### 9.2 输出 schema

```json
{
  "text": "续写正文",
  "choices": [
    {
      "choice_id": "c1",
      "label": "翻旧族谱",
      "intent": "身份揭露",
      "preview": "让身份有证可查",
      "tone": "克制"
    }
  ],
  "evidence_event_ids": ["sbtnn_001_0004"],
  "style_score": 0.82,
  "warnings": []
}
```

## 10. 如何用 AI 自动补全/编程

这块功能适合“规格先行 + AI 分步实现”，不要一次性让 AI 写完整功能。

### 10.1 给 AI 的上下文材料

把这些内容交给 Codex / Cursor / Copilot：

- 本文档。
- 现有 `backend/app/domains/narrative/*`。
- 现有 `flutter_app/lib/features/player/widgets/ai_branch_sheet.dart`。
- 现有 `flutter_app/lib/features/player/controllers/interaction_controller.dart`。
- 期望 API JSON 示例。

### 10.2 分任务提示词

任务 1：后端 schema

```text
根据 documents/AI_BRANCH_CHAT_STORY_DESIGN.md，实现 backend/app/domains/story_chat/schemas.py。
要求：
- 使用 Pydantic BaseModel。
- 包含 StoryThreadCreateIn、StoryChoiceIn、StoryTurnOut、StoryThreadOut、StoryThreadDeltaOut。
- 保持字段和文档一致。
- 先不要改业务逻辑。
```

任务 2：后端 service

```text
实现 StoryChatService.create_thread 和 choose。
复用 domains.narrative.NarrativeContextBuilder。
LLM 调用复用 services.ai_service.chat_completion。
失败时返回 fallback turn，不抛 500。
```

任务 3：Flutter 模型和 API

```text
在 flutter_app/lib/data/models.dart 增加 StoryThread、StoryTurn、StoryChoice。
在 ApiClient 增加 createStoryThread、chooseStoryBranch、sendStoryMessage。
不要删除旧 generateBranchStory。
```

任务 4：Flutter UI

```text
用 StoryChatSheet 替代 AiBranchSheet 的生成结果区域。
要求 turns 用 ListView 追加显示，点击最后一轮 choices 后 append 用户选择并继续请求。
保留点赞和评论入口。
```

### 10.3 AI 编程工具使用建议

- Cursor：把本文档放入 `documents`，可再建 `.cursor/rules/story-chat.md`，让 Agent 在相关文件上自动套用目录规范。Cursor 官方 docs 说明 rules 可放在 `.cursor/rules` 并随代码库版本管理。
- GitHub Copilot：适合小步补全模型类、fromJson/toJson、widget 拆分；官方文档支持 repository custom instructions，用来约束团队风格。
- Codex：适合跨前后端改造、跑测试、修编译错误；OpenAI Codex 官方介绍强调它能写功能、修 bug、回答代码库问题、提出 PR。

来源：

- [Cursor Rules](https://docs.cursor.com/en/context)
- [GitHub Copilot custom instructions](https://docs.github.com/en/copilot/concepts/prompting/response-customization)
- [OpenAI Codex](https://openai.com/codex/)

## 11. 落地顺序

推荐按这个顺序做：

1. 新增后端 `story_chat` schema 和假数据 service。
2. Flutter 新建 `StoryChatSheet`，先用本地 mock turns 跑通“不覆盖历史”。
3. 接 `/api/story-chat/threads`，实现第一轮自动生成。
4. 接 `/choose`，实现选择后继续追加。
5. 接 style profile，默认用 `cinematic_literary`。
6. 加 `retry/regenerate`，支持同一轮生成多个候选，不覆盖旧 turn。
7. 再把点赞、评论从 episode 级别改到 `turn_id` 级别。

## 12. 与当前代码的衔接点

当前已有这些基础，可以直接复用：

- `backend/app/api/branch_generation.py`：已有 `/api/branches/generate`。
- `backend/app/domains/narrative/*`：已有 PlotEvent、RoleCard、ContextBuilder、QualityGuard。
- `flutter_app/lib/data/api_client.dart`：已有 `generateBranchStoryFromEvidence`。
- `flutter_app/lib/features/player/widgets/ai_branch_sheet.dart`：可改造成第一版 Story Chat Sheet。

最小改造路径：

1. 先不要动后端，前端把 `generatedStory` 改成 `List<BranchStoryTurn>`。
2. 每次 `generateStory` 成功后 `storyTurns.add(...)`，而不是覆盖 `generatedStory`。
3. 点选项时先 append 用户选择，再请求 `generateBranchStoryFromEvidence`，成功后 append AI turn。
4. 等 UI 跑顺后，再补后端持久化和 `thread_id`。

