from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Float, Integer, JSON, String

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Teacher(Base):
    __tablename__ = "teachers"
    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    name = Column(String, nullable=False)
    class_code = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, default=_utcnow)


class User(Base):
    """设备级用户，不含 PII。游客 class_code 为空。"""
    __tablename__ = "users"
    device_id = Column(String, primary_key=True)
    apple_user_id = Column(String, index=True, nullable=True)  # Sign in with Apple 稳定标识
    nickname = Column(String, nullable=True)
    class_code = Column(String, index=True, nullable=True)
    role = Column(String, nullable=False, default="guest")
    experiment_group = Column(String, nullable=True)
    native_language = Column(String, nullable=True)
    spoken_languages = Column(JSON, nullable=True)   # 会说的语言列表（母语迁移分析）
    install_date = Column(DateTime, default=_utcnow)


class TrainingSession(Base):
    """声调训练记录（A/B 实验数据）。"""
    __tablename__ = "training_sessions"
    id = Column(String, primary_key=True)            # 客户端 UUID
    device_id = Column(String, index=True, nullable=False)
    class_code = Column(String, index=True, nullable=True)   # 空 = 未绑定班级池
    role = Column(String, nullable=False)
    group_assignment = Column(String, nullable=False)
    lexeme_id = Column(String, nullable=False)
    dtw_score = Column(Float, nullable=False)
    grade = Column(String, nullable=False)
    attempt_number = Column(Integer, nullable=False)
    timestamp = Column(DateTime, nullable=False)
    # 诊断埋点：区分"卡词/技术性失败/参照质量"，供数据自查
    reference_type = Column(String, nullable=True)          # real | tts | ideal
    voiced_frame_count = Column(Integer, nullable=True)
    quality_flag = Column(Boolean, nullable=True)           # 异常高分标记
    reference_switched = Column(Boolean, nullable=True)     # 应恒为 False
    phase = Column(String, nullable=True)                   # pretest | training | posttest
    app_version = Column(String, nullable=True)             # 如 "1.0 (16)"


class AspirationAttempt(Base):
    """送气训练记录（触发率数据）。"""
    __tablename__ = "aspiration_attempts"
    id = Column(String, primary_key=True)
    device_id = Column(String, index=True, nullable=False)
    class_code = Column(String, index=True, nullable=True)
    role = Column(String, nullable=False)
    target_word = Column(String, nullable=False)
    trigger_rate = Column(Float, nullable=False)
    passed = Column(Boolean, nullable=False)
    timestamp = Column(DateTime, nullable=False)


class FreeTextRecord(Base):
    """自由文本练习记录。"""
    __tablename__ = "freetext_records"
    id = Column(String, primary_key=True)
    device_id = Column(String, index=True, nullable=False)
    class_code = Column(String, index=True, nullable=True)
    role = Column(String, nullable=False)
    original_text = Column(String, nullable=False)
    tokenized_word = Column(String, nullable=False)
    pinyin = Column(String, nullable=False)
    tone_sequence = Column(JSON, nullable=True)
    f0_track = Column(JSON, nullable=True)
    duration = Column(Float, nullable=False)
    timestamp = Column(DateTime, nullable=False)
