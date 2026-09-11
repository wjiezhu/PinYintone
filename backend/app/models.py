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
    # 历史字段：旧版按学习者永久分组。受试内设计后仅作兼容保留，
    # **不得用于决定反馈呈现**（升级需求 §3.2）。
    experiment_group = Column(String, nullable=True)
    # 受试内 A/B 反平衡格子 0–3：决定哪个词集拿哪个条件、哪个条件先呈现
    counterbalance_index = Column(Integer, nullable=True)  # 历史列，A/B 取消后停写
    native_language = Column(String, nullable=True)
    spoken_languages = Column(JSON, nullable=True)   # 会说的语言列表（母语迁移分析）
    install_date = Column(DateTime, default=_utcnow)


class TrainingSession(Base):
    """声调训练记录。

    group_assignment = **该条记录所用的反馈条件**（绑定词集，受试内设计），
    不是"该学习者所属实验组"；测试阶段无条件，值为 "n/a"。
    """
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
    # 研究字段（升级需求 §3.1 / §3.2）
    phase = Column(String, index=True, nullable=True)        # pretest|training|posttest
    word_set_id = Column(String, nullable=True)              # set1|set2|assessment
    presentation_order = Column(String, nullable=True)       # 历史列，A/B 取消后停写
    assessment_set_version = Column(String, nullable=True)   # 仅测试词集记录有值
    # 记录语义与版本（升级需求 §6.1 / §6.2）
    # presentation_order / group_assignment 是 A/B 时期的历史列，schema_version >= 3 停写。
    # feedback_mode 仍在写：记的是**该条记录当时学习者自选的显示模式**（裸测为空）。
    # 注意 v3 与 v1/v2 语义不同——v1/v2 是随机分配的实验条件，v3 是自选偏好，
    # **不可混在一起分析**，也不得拿 v3 的值做组间比较（自选择偏差）。
    feedback_mode = Column(String, nullable=True)            # staticColor|dynamicF0|NULL(裸测)
    result_status = Column(String, index=True, nullable=True)  # valid_result|technical_retry|quality_flagged
    failure_reason = Column(String, nullable=True)           # 仅技术失败记录有值
    schema_version = Column(Integer, nullable=True)          # 记录字段版本；NULL 视为 1
    app_version = Column(String, nullable=True)              # 产生该记录的 App 版本


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
    phase = Column(String, index=True, nullable=True)
    schema_version = Column(Integer, nullable=True)
    app_version = Column(String, nullable=True)


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
    phase = Column(String, index=True, nullable=True)
    schema_version = Column(Integer, nullable=True)
    app_version = Column(String, nullable=True)
