import random
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from sqlalchemy.orm import Session

from . import models
from .config import settings


def hash_password(password: str) -> str:
    # bcrypt 仅取前 72 字节；超长需手动截断
    pw = password.encode("utf-8")[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8")[:72], hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_access_token(teacher_id: int) -> str:
    payload = {
        "sub": str(teacher_id),
        "exp": datetime.now(timezone.utc) + timedelta(hours=settings.jwt_expire_hours),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> int:
    data = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    return int(data["sub"])


def generate_class_code(db: Session) -> str:
    """6 位纯数字，全局唯一，禁止全同位（CLAUDE.md）。"""
    for _ in range(200):
        code = f"{random.randint(0, 999999):06d}"
        if len(set(code)) == 1:           # 000000 / 111111 等全同位
            continue
        exists = db.query(models.Teacher).filter(models.Teacher.class_code == code).first()
        if not exists:
            return code
    raise RuntimeError("无法生成唯一班级码")
