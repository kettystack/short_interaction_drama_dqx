# 《天下第一纨绔》个性化分支视频预生成说明

## 实现结果

- 24 集各配置一个主要剧情分支点。
- 每个分支点配置 3 个方向不同的选项。
- 目标共 72 条 Seedance 正片首帧图生视频。
- 生成任务支持断点续跑、并发限制、失败重试和进度清单。
- 批处理按选项轮询 24 集，优先保证每集先获得一条候选视频。
- 只有质量闸门通过的视频才会被普通用户播放。
- 普通用户的选项与素材库使用相同人工上下文和缓存键，不会重复付费生成。

## 人工上下文

人工校准数据位于：

```text
data/branch_context_overrides/tianxiadyi.json
```

每个关键点可以配置：

- `trigger_source` / `trigger_ts`：人工指定真正适合分支的正片时刻，可覆盖错误的自动高光点。
- `previous_context`：触发前发生了什么。
- `current_conflict`：当前真正需要解决的冲突。
- `next_main_event`：恢复正片后即将发生什么。
- `active_characters`：允许出现在插片中的角色。
- `opening_continuity`：首帧站位、服装、道具和光线约束。
- `dialogue_tone`：符合人物身份的一句短对白。
- `ending_bridge`：插片最后一拍如何接回正片。
- `options`：三个选项各自的动作、情绪和可见结果。

修改上下文文件的 `version` 或具体字段会进入视频缓存键，从而生成新版本，不会误用旧视频。
服务每次加载剧集时会校验当前人工点位；已废弃的旧人工点位不会继续展示。

## 生成数据流

```text
人工上下文 + 当前高光 + 正片首帧
  -> 固定的三个剧情选项
  -> 12 秒起承转合故事规划
  -> 三镜头规划
  -> Seedance 首帧图生视频
  -> 下载与 720x1280 转码
  -> 首帧 SSIM + 多模态剧情质检
  -> published / review_required / failed
  -> App 点击选项直接播放
  -> 插片结束回到 resume_at
```

## 批量命令

```bash
backend/.venv/bin/python scripts/pregen_branch_video_catalog.py \
  --prefix txy_ \
  --options-per-point 3 \
  --concurrency 6 \
  --poll-seconds 10 \
  --max-attempts 4
```

只重跑一集：

```bash
backend/.venv/bin/python scripts/pregen_branch_video_catalog.py \
  --episode-id txy_004 \
  --concurrency 3 \
  --max-attempts 4
```

进度文件：

```text
data/generated/branch_catalog/tianxiadyi_progress.json
```

任务可以重复执行。已发布的视频会直接跳过；失败但未达到最大尝试次数的任务会重新提交。
若 Seedance 返回 `AccountOverdueError`，脚本会立即暂停；充值后执行同一命令即可续跑。

欠费期间只查询和收割已经提交的任务，不再创建新任务：

```bash
backend/.venv/bin/python scripts/pregen_branch_video_catalog.py \
  --poll-existing-only \
  --concurrency 6 \
  --poll-seconds 10
```

## 质量原则

- 不能因为要凑齐三条视频而绕过质量闸门。
- 人脸、人物数量、古装场景或动作连续性明显偏离时必须拒绝。
- 连续失败的选项应修改动作复杂度或人物数量，再提高人工上下文版本重新生成。
- 优先使用单人或双人、单地点、单一明确动作；12 秒内不要安排跨场景剧情。
