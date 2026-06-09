from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy import text

from .config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(
    settings.database_url,
    echo=False,
    future=True,
    pool_size=10,
    max_overflow=20,
    pool_timeout=15,
    pool_pre_ping=True,
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


async def init_db() -> None:
    # 导入 models 触发注册
    from . import models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _ensure_interaction_event_columns(conn)
        await _ensure_danmaku_setting_columns(conn)


async def _ensure_interaction_event_columns(conn) -> None:
    dialect = conn.dialect.name
    if dialect == "postgresql":
        await conn.execute(text("ALTER TABLE interaction_events ADD COLUMN IF NOT EXISTS client_event_id VARCHAR(128)"))
        await conn.execute(text("ALTER TABLE interaction_events ADD COLUMN IF NOT EXISTS effect VARCHAR(64)"))
        await conn.execute(text("ALTER TABLE interaction_events ADD COLUMN IF NOT EXISTS payload_json JSON"))
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_interaction_events_client_event_id ON interaction_events (client_event_id)")
        )
        return

    if dialect == "sqlite":
        result = await conn.exec_driver_sql("PRAGMA table_info(interaction_events)")
        existing_columns = {row[1] for row in result.fetchall()}
        if "client_event_id" not in existing_columns:
            await conn.exec_driver_sql("ALTER TABLE interaction_events ADD COLUMN client_event_id VARCHAR(128)")
        if "effect" not in existing_columns:
            await conn.exec_driver_sql("ALTER TABLE interaction_events ADD COLUMN effect VARCHAR(64)")
        if "payload_json" not in existing_columns:
            await conn.exec_driver_sql("ALTER TABLE interaction_events ADD COLUMN payload_json JSON")
        await conn.exec_driver_sql(
            "CREATE INDEX IF NOT EXISTS ix_interaction_events_client_event_id ON interaction_events (client_event_id)"
        )


async def _ensure_danmaku_setting_columns(conn) -> None:
    dialect = conn.dialect.name
    if dialect == "postgresql":
        await conn.execute(text("ALTER TABLE danmaku_settings ADD COLUMN IF NOT EXISTS display_mode VARCHAR(24) DEFAULT 'standard'"))
        return

    if dialect == "sqlite":
        result = await conn.exec_driver_sql("PRAGMA table_info(danmaku_settings)")
        existing_columns = {row[1] for row in result.fetchall()}
        if "display_mode" not in existing_columns:
            await conn.exec_driver_sql("ALTER TABLE danmaku_settings ADD COLUMN display_mode VARCHAR(24) DEFAULT 'standard'")
