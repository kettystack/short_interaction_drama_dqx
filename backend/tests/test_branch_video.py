from __future__ import annotations

import unittest

from backend.app.domains.branch_video.cache import build_variant_cache_key
from backend.app.domains.branch_video.schemas import (
    BranchOptionPlan,
    BranchStoryPlan,
    BranchVideoContext,
)
from backend.app.domains.branch_video.shot_planner import build_shot_plan


class BranchVideoDomainTest(unittest.TestCase):
    def setUp(self) -> None:
        self.context = BranchVideoContext(
            episode_id="ep_test",
            drama_id="drama_test",
            episode_title="测试第1集",
            trigger_source="highlight",
            trigger_ts=56,
            resume_at=61,
            current_conflict="对手逼到面前",
            source_frame_url="/frames/ep_test/frame_56.jpg",
        )

    def test_different_options_have_different_cache_keys(self) -> None:
        option_a = BranchOptionPlan(
            option_key="A",
            label="正面反击",
            description="当场反制",
            action="反击",
            emotion="燃",
        )
        option_b = BranchOptionPlan(
            option_key="B",
            label="暗中设局",
            description="暂时示弱",
            action="设局",
            emotion="悬疑",
        )
        key_a = build_variant_cache_key(
            self.context,
            option_a,
            duration=12,
            prompt_version="v1",
        )
        key_b = build_variant_cache_key(
            self.context,
            option_b,
            duration=12,
            prompt_version="v1",
        )
        self.assertNotEqual(key_a, key_b)

    def test_shot_plan_is_three_beats_and_vertical(self) -> None:
        story = BranchStoryPlan(
            premise="主角决定反击",
            opening_continuity="从正片首帧开始",
            beats=["先稳住对方", "抓住破绽反制", "留下新的线索"],
            ending_hook="回到主线",
        )
        plan = build_shot_plan(self.context, story, target_duration=12)
        self.assertEqual(plan.aspect_ratio, "9:16")
        self.assertEqual(plan.duration, 12)
        self.assertEqual(len(plan.shots), 3)
        self.assertEqual(plan.shots[0].start, 0)
        self.assertEqual(plan.shots[-1].end, 12)


if __name__ == "__main__":
    unittest.main()
