from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .database import Base, engine
from .routers import auth, sync, teacher

# 开发期自动建表（生产建议改用 Alembic 迁移）
Base.metadata.create_all(bind=engine)

# 轻量迁移：create_all 不会给已存在的表加新列，这里补 Sign in with Apple 标识列
with engine.connect() as _conn:
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_user_id VARCHAR"))
    _conn.execute(text(
        "CREATE INDEX IF NOT EXISTS ix_users_apple_user_id ON users (apple_user_id)"))
    _conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS spoken_languages JSONB"))
    # 关卡 2 诊断埋点列
    for _ddl in (
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS reference_type VARCHAR",
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS voiced_frame_count INTEGER",
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS quality_flag BOOLEAN",
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS reference_switched BOOLEAN",
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS phase VARCHAR",
        "ALTER TABLE training_sessions ADD COLUMN IF NOT EXISTS app_version VARCHAR",
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


@app.get("/health")
def health():
    return {"status": "ok"}
