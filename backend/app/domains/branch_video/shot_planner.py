from __future__ import annotations

from .schemas import BranchShot, BranchShotPlan, BranchStoryPlan, BranchVideoContext


def build_shot_plan(
    context: BranchVideoContext,
    story: BranchStoryPlan,
    *,
    target_duration: float,
) -> BranchShotPlan:
    duration = max(4.0, min(float(target_duration), 15.0))
    first_end = round(duration * 0.28, 2)
    second_end = round(duration * 0.68, 2)
    beats = list(story.beats)
    while len(beats) < 3:
        beats.append(story.ending_hook)
    return BranchShotPlan(
        duration=duration,
        source_frame_url=context.source_frame_url,
        shots=[
            BranchShot(
                start=0,
                end=first_end,
                framing="中近景",
                action=beats[0],
                camera="从正片首帧轻微推进，不切换场景",
            ),
            BranchShot(
                start=first_end,
                end=second_end,
                framing="动作中景与局部特写",
                action=beats[1],
                camera="跟随核心动作，保持人物轴线稳定",
            ),
            BranchShot(
                start=second_end,
                end=duration,
                framing="双人中景或主角近景",
                action=f"{beats[2]}，以可回到正片的停顿收束",
                camera="稳定收束，避免新增不可逆剧情事实",
            ),
        ],
        negative_constraints=[
            *story.negative_constraints,
            "避免面部漂移、肢体融合、多余手指和画面文字乱码",
            "禁止文生视频式随机换景，必须从输入首帧连续生成",
        ],
    )
