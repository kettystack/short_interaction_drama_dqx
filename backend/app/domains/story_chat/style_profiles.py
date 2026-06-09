from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class StoryStyleProfile:
    code: str
    name: str
    prompt: str
    temperature: float = 0.72


_PROFILES: dict[str, StoryStyleProfile] = {
    "cinematic_literary": StoryStyleProfile(
        code="cinematic_literary",
        name="文艺电影感",
        prompt=(
            "画面感强，句子克制，少喊口号，多写动作、停顿、光线和人物微表情。"
            "保留短剧推进，但避免网络爽文腔。"
        ),
        temperature=0.68,
    ),
    "suspense_noir": StoryStyleProfile(
        code="suspense_noir",
        name="克制悬疑感",
        prompt="节奏压低，信息一点点露出，人物话里有话，结尾留下一个具体钩子。",
        temperature=0.7,
    ),
    "short_drama_punchy": StoryStyleProfile(
        code="short_drama_punchy",
        name="短剧高爽感",
        prompt="节奏快，冲突强，反转明确，适合短视频观看，但避免粗糙口水话。",
        temperature=0.78,
    ),
    "classical_chapter": StoryStyleProfile(
        code="classical_chapter",
        name="古风章回感",
        prompt="适合古装题材，语言有章回余味，但不写成文言文，台词自然。",
        temperature=0.72,
    ),
}


def get_style_profile(code: str | None) -> StoryStyleProfile:
    if code and code in _PROFILES:
        return _PROFILES[code]
    return _PROFILES["cinematic_literary"]

