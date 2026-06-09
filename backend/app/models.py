from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class Episode(Base):
    __tablename__ = "episodes"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # ep_063
    drama_id: Mapped[str] = mapped_column(String(64), index=True)   # beipaixunbao
    title: Mapped[str] = mapped_column(String(256))
    episode_no: Mapped[int] = mapped_column(Integer)
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    video_url: Mapped[str] = mapped_column(String(512))
    cover_url: Mapped[str] = mapped_column(String(512), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    highlights: Mapped[list["Highlight"]] = relationship(back_populates="episode", cascade="all, delete")


class EpisodeAsset(Base):
    __tablename__ = "episode_assets"
    __table_args__ = (UniqueConstraint("episode_id", "kind", "label", name="uq_episode_asset_variant"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    kind: Mapped[str] = mapped_column(String(32), default="hls")
    label: Mapped[str] = mapped_column(String(32), default="master")
    url: Mapped[str] = mapped_column(String(512))
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    bandwidth: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_ready: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    storage: Mapped[str] = mapped_column(String(32), default="local")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class TranscodeJob(Base):
    __tablename__ = "transcode_jobs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    status: Mapped[str] = mapped_column(String(32), default="queued", index=True)
    source_url: Mapped[str] = mapped_column(String(512), default="")
    output_url: Mapped[str] = mapped_column(String(512), default="")
    error_message: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class DanmakuItem(Base):
    __tablename__ = "danmaku_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float, index=True)
    text: Mapped[str] = mapped_column(String(256))
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    source: Mapped[str] = mapped_column(String(64), default="import")
    user_id: Mapped[str] = mapped_column(String(64), default="imported")
    lane: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="visible", index=True)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class DanmakuSetting(Base):
    __tablename__ = "danmaku_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    display_mode: Mapped[str] = mapped_column(String(24), default="standard")
    font_size: Mapped[float] = mapped_column(Float, default=16.0)
    opacity: Mapped[float] = mapped_column(Float, default=0.85)
    speed: Mapped[float] = mapped_column(Float, default=1.0)
    area: Mapped[float] = mapped_column(Float, default=1.0)
    duration: Mapped[float] = mapped_column(Float, default=8.0)
    time_offset: Mapped[float] = mapped_column(Float, default=0.0)
    show_top: Mapped[bool] = mapped_column(Boolean, default=True)
    show_bottom: Mapped[bool] = mapped_column(Boolean, default=True)
    show_scroll: Mapped[bool] = mapped_column(Boolean, default=True)
    follow_speed: Mapped[bool] = mapped_column(Boolean, default=True)
    line_height: Mapped[float] = mapped_column(Float, default=1.6)
    blocked_words: Mapped[list[str]] = mapped_column(JSON, default=list)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PlaybackProgress(Base):
    __tablename__ = "playback_progress"
    __table_args__ = (UniqueConstraint("user_id", "episode_id", name="uq_playback_progress_user_episode"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    progress_seconds: Mapped[float] = mapped_column(Float, default=0.0)
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, index=True)


class UserEpisodeAction(Base):
    __tablename__ = "user_episode_actions"
    __table_args__ = (UniqueConstraint("user_id", "episode_id", "action", name="uq_user_episode_action"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    action: Mapped[str] = mapped_column(String(32), index=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PlaybackEvent(Base):
    __tablename__ = "playback_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(64), default="anon", index=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    event_type: Mapped[str] = mapped_column(String(32), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float, default=0.0)
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    payload_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class Highlight(Base):
    __tablename__ = "highlights"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_start: Mapped[float] = mapped_column(Float)
    ts_end: Mapped[float] = mapped_column(Float)
    type: Mapped[str] = mapped_column(String(32))            # 冲突/反转/甜蜜/搞笑/名场面
    interaction: Mapped[str] = mapped_column(String(32))     # 爽/笑/哭/虐
    intensity: Mapped[float] = mapped_column(Float, default=0.5)
    description: Mapped[str] = mapped_column(Text, default="")
    raw: Mapped[dict] = mapped_column(JSON, default=dict)

    episode: Mapped[Episode] = relationship(back_populates="highlights")


class InteractionEvent(Base):
    __tablename__ = "interaction_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    client_event_id: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    episode_id: Mapped[str] = mapped_column(String(64), index=True)
    highlight_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    user_id: Mapped[str] = mapped_column(String(64), default="anon")
    action: Mapped[str] = mapped_column(String(64))          # 爽/笑/哭/branch_choice...
    effect: Mapped[str | None] = mapped_column(String(64), nullable=True)
    ts_in_video: Mapped[float] = mapped_column(Float)
    payload_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)

class BranchFork(Base):
    """剧情分叉点：在某集/某分支的某个时间点出现选项。"""
    __tablename__ = "branch_forks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float)            # 何时出现选择卡
    parent_branch_id: Mapped[int | None] = mapped_column(
        ForeignKey("branches.id"), nullable=True
    )  # NULL = 主线；非空 = 在该分支番出后内部的下一个叉
    prompt_text: Mapped[str] = mapped_column(String(256), default="接下来怎么走？")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    branches: Mapped[list["Branch"]] = relationship(
        back_populates="fork",
        foreign_keys="Branch.fork_id",
        cascade="all, delete",
    )


class Branch(Base):
    """分支选项：对应一个已剪辑好的视频片段。"""
    __tablename__ = "branches"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fork_id: Mapped[int] = mapped_column(ForeignKey("branch_forks.id"), index=True)
    choice_label: Mapped[str] = mapped_column(String(64))        # “假意接钱伺机反击”
    video_url: Mapped[str] = mapped_column(String(512))          # /videos/branches/xxx.mp4
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    order_idx: Mapped[int] = mapped_column(Integer, default=0)
    description: Mapped[str] = mapped_column(Text, default="")
    next_fork_id: Mapped[int | None] = mapped_column(
        ForeignKey("branch_forks.id"), nullable=True
    )  # 该分支播完后是否进入下一个叉
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    fork: Mapped[BranchFork] = relationship(
        back_populates="branches",
        foreign_keys=[fork_id],
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(64), default="")
    role: Mapped[str] = mapped_column(String(24), default="viewer", index=True)
    status: Mapped[str] = mapped_column(String(24), default="active", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class DeviceSession(Base):
    __tablename__ = "device_sessions"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    device_id: Mapped[str] = mapped_column(String(128), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(128))
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class AigcVideoJob(Base):
    __tablename__ = "aigc_video_jobs"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    ts_in_video: Mapped[float] = mapped_column(Float, default=0.0)
    trigger_type: Mapped[str] = mapped_column(String(32), default="boost", index=True)
    prompt: Mapped[str] = mapped_column(Text, default="")
    source_context: Mapped[dict] = mapped_column(JSON, default=dict)
    provider: Mapped[str] = mapped_column(String(32), default="mock")
    provider_job_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="queued", index=True)
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    source_video_url: Mapped[str] = mapped_column(String(512), default="")
    output_video_url: Mapped[str] = mapped_column(String(512), default="")
    hls_url: Mapped[str] = mapped_column(String(512), default="")
    cover_url: Mapped[str] = mapped_column(String(512), default="")
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    resume_at: Mapped[float] = mapped_column(Float, default=0.0)
    error_message: Mapped[str] = mapped_column(Text, default="")
    cost_cents: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class ClipAsset(Base):
    __tablename__ = "clip_assets"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    drama_id: Mapped[str] = mapped_column(String(64), index=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    source_video_url: Mapped[str] = mapped_column(String(512), default="")
    clip_url: Mapped[str] = mapped_column(String(512), default="")
    ts_start: Mapped[float] = mapped_column(Float, default=0.0)
    ts_end: Mapped[float] = mapped_column(Float, default=0.0)
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    characters: Mapped[list[str]] = mapped_column(JSON, default=list)
    location: Mapped[str] = mapped_column(String(128), default="")
    action_tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    emotion_tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    visual_tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    transcript: Mapped[str] = mapped_column(Text, default="")
    embedding_id: Mapped[str] = mapped_column(String(128), default="")
    source: Mapped[str] = mapped_column(String(32), default="auto")
    status: Mapped[str] = mapped_column(String(32), default="enabled", index=True)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AigcQualityCheck(Base):
    __tablename__ = "aigc_quality_checks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_id: Mapped[str] = mapped_column(ForeignKey("aigc_video_jobs.id"), index=True)
    candidate_url: Mapped[str] = mapped_column(String(512), default="")
    context_score: Mapped[float] = mapped_column(Float, default=0.0)
    character_score: Mapped[float] = mapped_column(Float, default=0.0)
    action_score: Mapped[float] = mapped_column(Float, default=0.0)
    style_score: Mapped[float] = mapped_column(Float, default=0.0)
    final_score: Mapped[float] = mapped_column(Float, default=0.0)
    final_decision: Mapped[str] = mapped_column(String(32), default="review", index=True)
    reasons: Mapped[list[str]] = mapped_column(JSON, default=list)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class AigcBoostPoint(Base):
    __tablename__ = "aigc_boost_points"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    trigger_ts: Mapped[float] = mapped_column(Float, default=0.0, index=True)
    resume_at: Mapped[float] = mapped_column(Float, default=0.0)
    title: Mapped[str] = mapped_column(String(128), default="加速包")
    prompt: Mapped[str] = mapped_column(Text, default="")
    provider: Mapped[str] = mapped_column(String(32), default="mock")
    source_job_id: Mapped[str] = mapped_column(String(96), default="", index=True)
    output_video_url: Mapped[str] = mapped_column(String(512), default="")
    hls_url: Mapped[str] = mapped_column(String(512), default="")
    cover_url: Mapped[str] = mapped_column(String(512), default="")
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    status: Mapped[str] = mapped_column(String(32), default="published", index=True)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PersonalizedBranchSession(Base):
    __tablename__ = "personalized_branch_sessions"
    __table_args__ = (
        UniqueConstraint(
            "episode_id",
            "user_id",
            "trigger_source",
            "trigger_ts",
            name="uq_branch_session_user_trigger",
        ),
    )

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    fork_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    highlight_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    user_id: Mapped[str] = mapped_column(String(64), default="anon", index=True)
    trigger_source: Mapped[str] = mapped_column(String(32), default="highlight", index=True)
    trigger_ts: Mapped[float] = mapped_column(Float, default=0.0, index=True)
    resume_at: Mapped[float] = mapped_column(Float, default=0.0)
    question: Mapped[str] = mapped_column(String(256), default="接下来要怎么面对？")
    context_snapshot: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(32), default="planned", index=True)
    prompt_version: Mapped[str] = mapped_column(String(64), default="branch-video-v1")
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PersonalizedBranchOption(Base):
    __tablename__ = "personalized_branch_options"
    __table_args__ = (
        UniqueConstraint("session_id", "option_key", name="uq_branch_option_key"),
    )

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    session_id: Mapped[str] = mapped_column(
        ForeignKey("personalized_branch_sessions.id"),
        index=True,
    )
    option_key: Mapped[str] = mapped_column(String(32))
    label: Mapped[str] = mapped_column(String(96))
    description: Mapped[str] = mapped_column(Text, default="")
    intent: Mapped[dict] = mapped_column(JSON, default=dict)
    user_prompt: Mapped[str] = mapped_column(Text, default="")
    story_plan: Mapped[dict] = mapped_column(JSON, default=dict)
    shot_plan: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(32), default="planned", index=True)
    order_idx: Mapped[int] = mapped_column(Integer, default=0)
    selected_count: Mapped[int] = mapped_column(Integer, default=0)
    error_message: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class BranchVideoVariant(Base):
    __tablename__ = "branch_video_variants"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    option_id: Mapped[str] = mapped_column(
        ForeignKey("personalized_branch_options.id"),
        index=True,
    )
    aigc_job_id: Mapped[str | None] = mapped_column(
        ForeignKey("aigc_video_jobs.id"),
        nullable=True,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(32), default="")
    model: Mapped[str] = mapped_column(String(128), default="")
    source_frame_url: Mapped[str] = mapped_column(String(512), default="")
    output_video_url: Mapped[str] = mapped_column(String(512), default="")
    duration: Mapped[float] = mapped_column(Float, default=0.0)
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    quality_detail: Mapped[dict] = mapped_column(JSON, default=dict)
    review_status: Mapped[str] = mapped_column(String(32), default="pending", index=True)
    publish_status: Mapped[str] = mapped_column(String(32), default="draft", index=True)
    cache_key: Mapped[str] = mapped_column(String(128), default="", unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class BranchPlaybackEvent(Base):
    __tablename__ = "branch_playback_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(String(96), index=True)
    option_id: Mapped[str] = mapped_column(String(96), index=True)
    variant_id: Mapped[str] = mapped_column(String(96), index=True)
    user_id: Mapped[str] = mapped_column(String(64), default="anon", index=True)
    event_type: Mapped[str] = mapped_column(String(32), index=True)
    ts_in_main_video: Mapped[float] = mapped_column(Float, default=0.0)
    clip_position: Mapped[float] = mapped_column(Float, default=0.0)
    client_event_id: Mapped[str] = mapped_column(String(128), default="", index=True)
    payload_json: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class HighlightGoldLabel(Base):
    __tablename__ = "highlight_gold_labels"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    ts_start: Mapped[float] = mapped_column(Float)
    ts_end: Mapped[float] = mapped_column(Float)
    type: Mapped[str] = mapped_column(String(32))
    interaction: Mapped[str] = mapped_column(String(32), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    annotator_id: Mapped[str] = mapped_column(String(64), default="admin")
    confidence: Mapped[float] = mapped_column(Float, default=1.0)
    source: Mapped[str] = mapped_column(String(32), default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class HighlightEvalRun(Base):
    __tablename__ = "highlight_eval_runs"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id"), index=True)
    pipeline_version: Mapped[str] = mapped_column(String(64), default="db_highlights")
    iou_threshold: Mapped[float] = mapped_column(Float, default=0.3)
    precision: Mapped[float] = mapped_column(Float, default=0.0)
    recall: Mapped[float] = mapped_column(Float, default=0.0)
    f1: Mapped[float] = mapped_column(Float, default=0.0)
    type_accuracy: Mapped[float] = mapped_column(Float, default=0.0)
    true_positive_count: Mapped[int] = mapped_column(Integer, default=0)
    false_positive_count: Mapped[int] = mapped_column(Integer, default=0)
    false_negative_count: Mapped[int] = mapped_column(Integer, default=0)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class HighlightEvalItem(Base):
    __tablename__ = "highlight_eval_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(ForeignKey("highlight_eval_runs.id"), index=True)
    gold_label_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    pred_highlight_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    match_type: Mapped[str] = mapped_column(String(16), index=True)
    iou: Mapped[float] = mapped_column(Float, default=0.0)
    type_match: Mapped[bool] = mapped_column(Boolean, default=False)
    note: Mapped[str] = mapped_column(Text, default="")


class ContentReviewItem(Base):
    __tablename__ = "content_review_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_type: Mapped[str] = mapped_column(String(32), index=True)
    item_id: Mapped[str] = mapped_column(String(128), index=True)
    episode_id: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    text: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[str] = mapped_column(String(32), default="pending", index=True)
    risk_score: Mapped[float] = mapped_column(Float, default=0.0)
    reason: Mapped[str] = mapped_column(Text, default="")
    reviewer_id: Mapped[str] = mapped_column(String(64), default="")
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class ModerationLog(Base):
    __tablename__ = "moderation_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    scene: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(64), default="anon", index=True)
    text: Mapped[str] = mapped_column(Text, default="")
    decision: Mapped[str] = mapped_column(String(32), default="allow", index=True)
    risk_score: Mapped[float] = mapped_column(Float, default=0.0)
    reasons: Mapped[list[str]] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class ModelCallLog(Base):
    __tablename__ = "model_call_logs"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), default="doubao")
    model: Mapped[str] = mapped_column(String(128), default="")
    scene: Mapped[str] = mapped_column(String(64), index=True)
    user_id: Mapped[str] = mapped_column(String(64), default="system", index=True)
    episode_id: Mapped[str] = mapped_column(String(64), default="", index=True)
    prompt_tokens: Mapped[int] = mapped_column(Integer, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cost_cents: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(32), default="ok", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class RateLimitBucket(Base):
    __tablename__ = "rate_limit_buckets"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True)
    route_group: Mapped[str] = mapped_column(String(64), index=True)
    window_start: Mapped[datetime] = mapped_column(DateTime)
    count: Mapped[int] = mapped_column(Integer, default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)


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
    status: Mapped[str] = mapped_column(String(32), default="visible", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class StoryTurnModel(Base):
    __tablename__ = "story_turns"

    id: Mapped[str] = mapped_column(String(96), primary_key=True)
    thread_id: Mapped[str] = mapped_column(ForeignKey("story_threads.id"), index=True)
    role: Mapped[str] = mapped_column(String(32), index=True)
    parent_turn_id: Mapped[str | None] = mapped_column(String(96), nullable=True)
    selected_choice_id: Mapped[str | None] = mapped_column(String(96), nullable=True)
    text: Mapped[str] = mapped_column(Text)
    choices: Mapped[list[dict]] = mapped_column(JSON, default=list)
    evidence_event_ids: Mapped[list[str]] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(32), default="visible", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


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
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_id: Mapped[str] = mapped_column(String(64), default="system", index=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    target_type: Mapped[str] = mapped_column(String(64), index=True)
    target_id: Mapped[str] = mapped_column(String(128), default="")
    payload_json: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)
