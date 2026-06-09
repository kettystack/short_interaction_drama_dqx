"""镜头切分候选：使用 PySceneDetect 找硬切点。

把每个 cut 作为高光窗口的代表时间戳；结合 audio_highlight 的能量峰
可大幅压缩送给 Doubao 多模态的窗口数（仅在"镜头变化 + 情绪能量高"
的地方判断高光），保留召回的同时节省 token 与时间。
"""
from __future__ import annotations

from pathlib import Path
from typing import TypedDict


class SceneCut(TypedDict):
    ts: float
    end: float


def detect_scene_cuts(
    video: Path,
    threshold: float = 27.0,
    min_scene_sec: float = 2.0,
) -> list[SceneCut]:
    """返回每个镜头的 [start, end] 秒。"""
    try:
        from scenedetect import open_video, SceneManager
        from scenedetect.detectors import ContentDetector
    except ImportError as e:  # 允许在未装可选依赖时优雅退化
        raise RuntimeError(
            "PySceneDetect 未安装，请 `pip install 'scenedetect[opencv]'`"
        ) from e

    vid = open_video(str(video))
    mgr = SceneManager()
    mgr.add_detector(ContentDetector(threshold=threshold, min_scene_len=int(min_scene_sec * 24)))
    mgr.detect_scenes(vid, show_progress=False)
    scenes = mgr.get_scene_list()
    out: list[SceneCut] = []
    for start, end in scenes:
        out.append({"ts": float(start.get_seconds()), "end": float(end.get_seconds())})
    return out


if __name__ == "__main__":
    import json
    import sys
    print(json.dumps(detect_scene_cuts(Path(sys.argv[1])), ensure_ascii=False, indent=2))
