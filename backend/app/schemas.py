from datetime import datetime

from pydantic import BaseModel, Field


class HighlightOut(BaseModel):
    id: int
    episode_id: str
    ts_start: float
    ts_end: float
    type: str
    interaction: str
    intensity: float
    description: str

    class Config:
        from_attributes = True


class HlsVariantOut(BaseModel):
    label: str
    url: str
    width: int | None = None
    height: int | None = None
    bandwidth: int | None = None


class EpisodeOut(BaseModel):
    id: str
    drama_id: str
    title: str
    episode_no: int
    duration: float
    video_url: str
    hls_url: str | None = None
    hls_ready: bool = False
    hls_variants: list[HlsVariantOut] = Field(default_factory=list)
    cover_url: str = ""

    class Config:
        from_attributes = True


class EpisodeAssetOut(BaseModel):
    id: int
    episode_id: str
    kind: str
    label: str
    url: str
    width: int | None = None
    height: int | None = None
    bandwidth: int | None = None
    is_ready: bool
    storage: str

    class Config:
        from_attributes = True


class DanmakuOut(BaseModel):
    id: int
    episode_id: str
    ts_in_video: float
    text: str
    like_count: int = 0
    lane: int | None = None
    source: str = "import"

    class Config:
        from_attributes = True


class DanmakuIn(BaseModel):
    episode_id: str
    ts_in_video: float
    text: str
    like_count: int = 0
    user_id: str = "anon"


class DanmakuReportIn(BaseModel):
    user_id: str = "anon"
    reason: str = "不适"


class DanmakuSettingsIn(BaseModel):
    enabled: bool = True
    display_mode: str = "standard"
    font_size: float = 16.0
    opacity: float = 0.85
    speed: float = 1.0
    area: float = 1.0
    duration: float = 8.0
    time_offset: float = 0.0
    show_top: bool = True
    show_bottom: bool = True
    show_scroll: bool = True
    follow_speed: bool = True
    line_height: float = 1.6
    blocked_words: list[str] = Field(default_factory=list)


class DanmakuSettingsOut(DanmakuSettingsIn):
    user_id: str
    updated_at: datetime | None = None

    class Config:
        from_attributes = True


class HotWordOut(BaseModel):
    text: str
    count: int


class PlaybackProgressIn(BaseModel):
    user_id: str = "anon"
    episode_id: str
    progress_seconds: float
    duration: float = 0.0
    completed: bool = False


class PlaybackProgressOut(BaseModel):
    user_id: str
    episode_id: str
    progress_seconds: float
    duration: float
    completed: bool
    updated_at: datetime

    class Config:
        from_attributes = True


class UserEpisodeActionIn(BaseModel):
    user_id: str = "anon"
    episode_id: str
    action: str
    active: bool = True


class UserEpisodeActionOut(BaseModel):
    user_id: str
    episode_id: str
    action: str
    active: bool
    updated_at: datetime

    class Config:
        from_attributes = True


class PlaybackEventIn(BaseModel):
    user_id: str = "anon"
    episode_id: str
    event_type: str
    ts_in_video: float = 0.0
    duration: float = 0.0
    payload: dict = Field(default_factory=dict)


class PlaybackEventOut(BaseModel):
    id: int
    user_id: str
    episode_id: str
    event_type: str
    ts_in_video: float
    duration: float
    created_at: datetime

    class Config:
        from_attributes = True


class TranscodeJobOut(BaseModel):
    id: int
    episode_id: str
    status: str
    source_url: str
    output_url: str
    error_message: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class InteractionIn(BaseModel):
    episode_id: str
    highlight_id: int | None = None
    action: str
    ts_in_video: float
    user_id: str = "anon"
    effect: str | None = None


class InteractionOut(BaseModel):
    id: int
    episode_id: str
    action: str
    ts_in_video: float
    created_at: datetime

    class Config:
        from_attributes = True


class InteractionSummaryOut(BaseModel):
    episode_id: str
    action: str
    count: int
    display_count: int
    label: str


class BranchStoryIn(BaseModel):
    episode_id: str
    context: str = Field(..., description="到目前为止的剧情摘要 / 用户输入")
    choice: str | None = None


class BranchStoryOut(BaseModel):
    text: str
    choices: list[str] = Field(default_factory=list, description="AI 生成的 3 个可选后续方向")


class PickFeedItemOut(BaseModel):
    episode: EpisodeOut
    score: float
    reason: str
    tags: list[str] = Field(default_factory=list)


class VipBenefitOut(BaseModel):
    code: str
    title: str
    subtitle: str = ""


class VipProfileOut(BaseModel):
    user_id: str
    display_name: str
    vip_level: int
    vip_badge: str
    goose_coins: int = 0
    diamonds: int = 0
    benefits: list[VipBenefitOut] = Field(default_factory=list)
    vip_episodes: list[EpisodeOut] = Field(default_factory=list)
