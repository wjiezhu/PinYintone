"""启动时的身份迁移：账号从「只认 Apple」改为「登录方式 + 该方式下的用户号」。

与 main.py 里的 ALTER 列表不同，这一步 SQLite 与 PostgreSQL 都要跑：
它不只是补列，还要搬数据，本地库与测试也得是同一结构。

全部操作幂等，放在一个事务里（两种库的 DDL 都是事务性的），中途失败整体回滚：
1. users 补 auth_provider / auth_subject / auth_verified_at / legacy_login_at；
2. 只有 apple_user_id 的旧行抄成 (apple, apple_user_id)——apple_user_id 本身不动；
3. 旧表 account_links（apple_user_id 主键）抄进 account_identities，
   provider 记为 apple，**account_id 原样不动**（研究身份按它，变了就是换了一个人）。

旧表**保留**，确认无误后由人手动清理（核对与清理语句见 backend/README.md）。
所以第 3 步**只做一次**，做完在 app_migrations 里记一笔：旧表还在，若每次启动都按
「新表里没有就补」再抄一遍，已删除的账号会被从旧表抄回来，删除就白做了。
搬完之后代码里任何地方都不再读写 account_links。
"""
from sqlalchemy import inspect, text

_NEW_USER_COLUMNS = (
    ("auth_provider", "VARCHAR", "VARCHAR"),
    ("auth_subject", "VARCHAR", "VARCHAR"),
    ("auth_verified_at", "TIMESTAMPTZ", "DATETIME"),
    ("legacy_login_at", "TIMESTAMPTZ", "DATETIME"),
)

ACCOUNT_LINKS_MIGRATION = "account_links_to_account_identities"


def migrate_account_identities(engine) -> None:
    """须在 `Base.metadata.create_all` 之后调用（account_identities 由它建出）。"""
    insp = inspect(engine)
    tables = set(insp.get_table_names())
    pg = engine.dialect.name == "postgresql"
    ts = "TIMESTAMPTZ" if pg else "DATETIME"
    with engine.begin() as conn:
        if "users" in tables:
            cols = {c["name"] for c in insp.get_columns("users")}
            for name, pg_type, sqlite_type in _NEW_USER_COLUMNS:
                if name not in cols:
                    conn.execute(text(
                        f"ALTER TABLE users ADD COLUMN {name} {pg_type if pg else sqlite_type}"))
            conn.execute(text("CREATE INDEX IF NOT EXISTS ix_users_auth_identity "
                              "ON users (auth_provider, auth_subject)"))
            if "apple_user_id" in cols:
                conn.execute(text(
                    "UPDATE users SET auth_provider = 'apple', auth_subject = apple_user_id "
                    "WHERE apple_user_id IS NOT NULL AND apple_user_id <> '' "
                    "AND auth_subject IS NULL"))

        conn.execute(text("CREATE TABLE IF NOT EXISTS app_migrations ("
                          f"name VARCHAR PRIMARY KEY, applied_at {ts} NOT NULL)"))
        done = conn.execute(text("SELECT 1 FROM app_migrations WHERE name = :n"),
                            {"n": ACCOUNT_LINKS_MIGRATION}).first()
        if done is None:
            if "account_links" in tables:
                conn.execute(text(
                    "INSERT INTO account_identities (provider, subject, account_id, created_at) "
                    "SELECT 'apple', l.apple_user_id, l.account_id, l.created_at "
                    "FROM account_links l WHERE NOT EXISTS ("
                    "SELECT 1 FROM account_identities i "
                    "WHERE i.provider = 'apple' AND i.subject = l.apple_user_id)"))
            # 新库（没有旧表）也记上：以后不会再去找旧表
            conn.execute(text("INSERT INTO app_migrations (name, applied_at) "
                              "VALUES (:n, CURRENT_TIMESTAMP)"), {"n": ACCOUNT_LINKS_MIGRATION})
