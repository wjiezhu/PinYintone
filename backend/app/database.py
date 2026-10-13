from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker

from .config import settings


def _normalize(url: str) -> str:
    """适配云平台（Railway/Render/Heroku）注入的 DATABASE_URL：
    将 postgres:// / postgresql:// 统一为 SQLAlchemy 需要的 postgresql+psycopg2://。"""
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg2://", 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg2://", 1)
    return url


DATABASE_URL = _normalize(settings.database_url)

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=connect_args, pool_pre_ping=True, future=True)


def enforce_sqlite_foreign_keys(target_engine) -> None:
    """让 SQLite 像 PostgreSQL 一样检查外键。

    SQLite 默认**不检查**外键。纳入接口曾经先插同意记录、后插参与者，
    本地与测试（SQLite）一直是绿的，到了线上 PostgreSQL 必然 500。
    打开检查后，这类顺序问题在本地和 CI 里就会暴露。
    """
    if target_engine.dialect.name != "sqlite":
        return

    @event.listens_for(target_engine, "connect")
    def _on_connect(dbapi_connection, _record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


enforce_sqlite_foreign_keys(engine)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
