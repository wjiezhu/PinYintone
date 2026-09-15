from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .database import Base, engine
# 新版研究表：import 即注册到 Base.metadata，由下面的 create_all 自动建表。
# 与旧表物理分离，旧表冻结只读。
from . import research_models  # noqa: F401
from .routers import auth, research, sync, teacher

# 开发期自动建表（生产建议改用 Alembic 迁移）
Base.metadata.create_all(bind=engine)

# 轻量迁移：create_all 不会给已存在的表加新列。
# 仅对 PostgreSQL 执行（生产环境）——SQLite 不支持 ADD COLUMN IF NOT EXISTS，
# 而本地 SQLite 开发库由 create_all 直接建成最新结构，无需补列。
if engine.dialect.name == "postgresql":
    with engine.connect() as _conn:
        for _ddl in (
            # Sign in with Apple 标识
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_user_id VARCHAR",
            "CREATE INDEX IF NOT EXISTS ix_users_apple_user_id ON users (apple_user_id)",
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS spoken_languages JSONB",
            # 受试内 A/B 反平衡格子（升级需求 §3.2）
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS counterbalance_index INTEGER",
            # 关卡 2 诊断埋点列
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS reference_type VARCHAR",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS voiced_frame_count INTEGER",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS quality_flag BOOLEAN",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS reference_switched BOOLEAN",
            # 研究字段（升级需求 §3.1 / §3.2）
            # 阶段列按档案统一命名为 phase（stage 一词在本工程里指关卡 1/2/3）
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS phase VARCHAR",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS word_set_id VARCHAR",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS presentation_order VARCHAR",
            "ALTER TABLE training_sessions "
            "ADD COLUMN IF NOT EXISTS assessment_set_version VARCHAR",
            "CREATE INDEX IF NOT EXISTS ix_training_sessions_phase "
            "ON training_sessions (phase)",
            "ALTER TABLE aspiration_attempts ADD COLUMN IF NOT EXISTS phase VARCHAR",
            "CREATE INDEX IF NOT EXISTS ix_aspiration_attempts_phase "
            "ON aspiration_attempts (phase)",
            "ALTER TABLE freetext_records ADD COLUMN IF NOT EXISTS phase VARCHAR",
            "CREATE INDEX IF NOT EXISTS ix_freetext_records_phase "
            "ON freetext_records (phase)",
            # 记录语义与版本（升级需求 §6.1 / §6.2）
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS feedback_mode VARCHAR",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS result_status VARCHAR",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS failure_reason VARCHAR",
            "CREATE INDEX IF NOT EXISTS ix_training_sessions_result_status "
            "ON training_sessions (result_status)",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS schema_version INTEGER",
            "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS app_version VARCHAR",
            "ALTER TABLE aspiration_attempts ADD COLUMN IF NOT EXISTS schema_version INTEGER",
            "ALTER TABLE aspiration_attempts ADD COLUMN IF NOT EXISTS app_version VARCHAR",
            "ALTER TABLE freetext_records ADD COLUMN IF NOT EXISTS schema_version INTEGER",
            "ALTER TABLE freetext_records ADD COLUMN IF NOT EXISTS app_version VARCHAR",
        ):
            _conn.execute(text(_ddl))
        _conn.commit()

app = FastAPI(title="Pinyintone Backend", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(sync.router)
app.include_router(teacher.router)
app.include_router(research.router)


@app.get("/health")
def health():
    return {"status": "ok"}
