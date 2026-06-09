from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# 始终从 backend/.env 加载，不依赖工作目录
_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_PROJECT_ROOT = _BACKEND_ROOT.parent
_WORKSPACE_ROOT = _PROJECT_ROOT.parent
_ENV_FILE = _BACKEND_ROOT / ".env"


def _path(value: Path) -> str:
    return str(value.resolve())


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(_ENV_FILE), extra="ignore")

    database_url: str = "postgresql+asyncpg://sdi:sdi@localhost:5432/sdi"
    redis_url: str = "redis://localhost:6379/0"
    ark_api_key: str = ""
    ark_endpoint: str = ""
    ark_base_url: str = "https://ark.cn-beijing.volces.com/api/v3"
    doubao_api_key: str = ""
    doubao_endpoint: str = ""
    story_chat_api_key: str = ""
    story_chat_endpoint: str = ""
    story_chat_base_url: str = ""
    story_chat_timeout_seconds: float = 60.0
    story_chat_max_tokens: int = 900
    admin_api_token: str = "local-admin-token"
    auth_token_secret: str = "local-dev-auth-secret"
    auth_access_token_ttl_minutes: int = 60 * 24
    public_base_url: str = "http://127.0.0.1:8000"
    aigc_video_provider: str = "hybrid"
    aigc_video_real_enabled: bool = False
    aigc_video_fallback_to_assets: bool = True
    aigc_video_endpoint_id: str = ""
    aigc_video_model: str = "doubao-seedance-1-0-pro-fast-251015"
    aigc_video_task_endpoint: str = "https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks"
    aigc_video_resolution: str = "720p"
    aigc_video_generate_audio: bool = False
    aigc_video_watermark: bool = False
    aigc_video_seed: int = -1
    aigc_video_quality_min_score: float = 0.58
    aigc_video_require_first_frame: bool = True
    aigc_video_multimodal_enabled: bool = True
    aigc_video_multimodal_endpoint: str = ""
    aigc_video_multimodal_api_key: str = ""
    aigc_video_auto_publish_min_score: float = 0.82
    aigc_video_review_min_score: float = 0.58
    aigc_video_transcode_enabled: bool = True
    aigc_video_target_width: int = 720
    aigc_video_target_height: int = 1280
    aigc_video_camera_fixed: bool = False
    aigc_video_first_frame_min_ssim: float = 0.72
    aigc_video_provider_max_duration_seconds: float = 12.0
    aigc_media_public_base_url: str = ""
    aigc_insert_duration_seconds: float = 12.0
    aigc_resume_offset_seconds: float = 5.0
    branch_video_enabled: bool = True
    branch_video_auto_prewarm: bool = True
    branch_video_prewarm_seconds: float = 60.0
    branch_video_trigger_window_seconds: float = 12.0
    branch_video_target_duration_seconds: float = 12.0
    branch_video_max_sessions_per_episode: int = 2
    branch_video_highlight_min_intensity: float = 0.78
    branch_video_allow_legacy_variants: bool = False
    generated_media_root: str = _path(_PROJECT_ROOT / "data" / "generated")
    text_moderation_block_words: str = "违法,辱骂,涉政敏感"
    rate_limit_enabled: bool = True
    story_chat_storage: str = "db"
    video_root: str = _path(_WORKSPACE_ROOT / "juben" / "beipaixunbao")
    tianxiadyi_video_root: str = _path(_WORKSPACE_ROOT / "juben" / "tianxiadyi")
    shibasuitainainai_video_root: str = _path(
        _WORKSPACE_ROOT / "juben" / "shibasuitainainai"
    )
    data_root: str = _path(_PROJECT_ROOT / "data")

    @field_validator(
        "video_root",
        "tianxiadyi_video_root",
        "shibasuitainainai_video_root",
        "data_root",
        "generated_media_root",
        mode="after",
    )
    @classmethod
    def resolve_local_path(cls, value: str) -> str:
        path = Path(value).expanduser()
        if path.is_absolute():
            return str(path.resolve())
        for base in (_BACKEND_ROOT, _PROJECT_ROOT, _WORKSPACE_ROOT):
            candidate = (base / path).resolve()
            if candidate.exists():
                return str(candidate)
        return str((_BACKEND_ROOT / path).resolve())


settings = Settings()
