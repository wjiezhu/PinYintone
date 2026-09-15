"""新版研究数据表（research_* 前缀）。

与旧表**物理分离**：旧表 `training_sessions` / `aspiration_attempts` / `freetext_records`
冻结只读、不再写入，新版研究数据只落本文件定义的表。
分表而非加标记，是因为「每个查询都记得加过滤条件」这个约定在本项目已被证伪过一次
（技术失败的哨兵值在 export.sql 里筛了、在 teacher.py 里漏了，导致班级均分虚高约 4 倍）。

字段定义严格对应《新版研究_数据表与字段字典_v1》。**不得擅自更改字段含义、
缺失规则或统计单位**；物理类型可按数据库调整。

通用约定（字典 §2）：
- 无观测值一律写 NULL，**不写 0、空字符串或虚构默认值**。
  旧表为绕开 NOT NULL 曾用 -1 哨兵，新表的 metric_value 本就可空，不再需要也不允许。
- 时间统一 UTC，客户端发生时间（occurred_at/started_at）与服务端接收时间
  （received_at）分开保存；时长用非负整数毫秒。
- 枚举按字典的英文编码保存为字符串；显示文字由客户端翻译。
- 测试数据必须 is_test=true。
"""

from datetime import datetime, timezone

from sqlalchemy import (Boolean, Column, DateTime, ForeignKey, Integer, JSON,
                        Numeric, String, UniqueConstraint)

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _ts(**kw):
    """带时区的时间戳列。"""
    return Column(DateTime(timezone=True), **kw)


class ResearchManifest(Base):
    """研究配置（字典 §3）。每行是一份**不可变**配置。

    评分、词库、提示或问卷发生实质变化时新建配置，**不覆盖旧配置**，
    使旧数据仍可追溯到当时的实际规则。
    """
    __tablename__ = "research_manifests"
    manifest_id = Column(String, primary_key=True)
    study_id = Column(String(64), nullable=False, index=True)
    app_version = Column(String(32), nullable=False)
    build_number = Column(String(32), nullable=False)
    lexicon_version = Column(String(64), nullable=False)
    scoring_version = Column(String(64), nullable=False)
    # metric_name / unit / direction(higher_better|lower_better) / min_value /
    # max_value / pass_threshold。未设上下界或阈值时对应值为 null。
    # ⚠ 本工程的通关判定是两级的（DTW ≤ 0.5 且未被平调词走向闸门拦下），
    #   单一 pass_threshold 表达不了，扩展方式见 docs/V2_DECISIONS.md 待确认 B。
    scoring_spec = Column(JSON, nullable=False)
    feedback_version = Column(String(64), nullable=False)
    advice_policy_version = Column(String(64), nullable=False)
    survey_version = Column(String(64), nullable=False)
    consent_version = Column(String(64), nullable=False)
    eligibility_version = Column(String(64), nullable=False)
    # adult_required / nationality_any / course_stage_any / new_user_required
    eligibility_spec = Column(JSON, nullable=False)
    post_trigger_count = Column(Integer, nullable=False)
    post_trigger_scope = Column(String(64), nullable=False)
    reward_rule_version = Column(String(64), nullable=True)   # 积分未上线则 NULL
    collection_start_at = _ts(nullable=False)
    collection_end_at = _ts(nullable=False)
    frozen_at = _ts(nullable=False)


class ResearchParticipant(Base):
    """研究参与者（字典 §4）。一行 = 一名参与者，**不是**一次登录或一次安装。

    背景原始回答在问卷表，本表不重复维护国籍/语言/水平副本。
    """
    __tablename__ = "research_participants"
    participant_id = Column(String, primary_key=True)      # 随机研究编号
    study_id = Column(String(64), nullable=False, index=True)
    enrolled_at = _ts(nullable=False)
    eligibility_version = Column(String(64), nullable=False)
    eligibility_status = Column(String(16), nullable=False)   # eligible|excluded|pending
    # excluded 时必填：age|nationality|course_stage|withdrawn|duplicate|other
    exclusion_reason = Column(String(32), nullable=True)
    distribution_channel = Column(String(32), nullable=False)
    recruitment_source = Column(String(32), nullable=False)
    # new|returning|unknown。本轮仅 new 可纳入。
    prior_use_status = Column(String(16), nullable=False)
    # verified_account_history|self_report|combined|insufficient
    #
    # 本工程可达到 verified_account_history：旧版学生注册强制 Sign in with Apple
    # 且无游客练习路径，故 Apple ID 命中旧 users 表即可确证为旧用户。
    # ⚠ 反向不成立——查不到只说明「无证据表明用过」，换过 Apple 账号或
    #   旧版下载未注册者会看起来像新用户，此类只能记 insufficient。
    prior_use_evidence = Column(String(32), nullable=False)
    is_test = Column(Boolean, nullable=False, default=False)


class ResearchIdentityMap(Base):
    """账号映射（字典 §4 末）。**受限业务表，不进入论文导出。**

    研究编号与业务账号的唯一关联点。因存在此映射，研究数据称为
    「去标识化」而非不可逆匿名化。**不得直接使用 Apple 标识作研究编号。**
    """
    __tablename__ = "research_identity_map"
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            primary_key=True)
    internal_user_id = Column(String, nullable=False, index=True)
    study_id = Column(String(64), nullable=False)
    created_at = _ts(nullable=False, default=_utcnow)
    __table_args__ = (UniqueConstraint("internal_user_id", "study_id",
                                       name="uq_identity_user_study"),)


class ResearchConsentEvent(Base):
    """同意状态变更（字典 §5）。**追加保存，不覆盖历史。**

    拒绝研究时不必创建参与者；客户端本地记住拒绝状态即可，避免反复提示。
    首次同意需联网确认后才开启研究上传，**不回补此前的行为**。
    """
    __tablename__ = "research_consent_events"
    consent_event_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    action = Column(String(16), nullable=False)            # granted|withdrawn
    consent_version = Column(String(64), nullable=False)   # 用户**实际看到**的文本版本
    language = Column(String(32), nullable=False)          # 实际显示语言
    occurred_at = _ts(nullable=False)
    received_at = _ts(nullable=False)


class ResearchLexeme(Base):
    """词条版本（字典 §6）。词条内容或示范改变即新建一行。"""
    __tablename__ = "research_lexemes"
    lexeme_version_id = Column(String, primary_key=True)
    lexeme_id = Column(String(64), nullable=False, index=True)   # 跨版本稳定编号
    lexicon_version = Column(String(64), nullable=False)
    hanzi = Column(String(128), nullable=False)
    pinyin = Column(String(256), nullable=False)
    # 按音节排列，1/2/3/4/**0 表示轻声**。
    # ⚠ 现有 Swift 代码与 lexemes.json 用 5 表示轻声，写入本表前必须换算。
    citation_tones = Column(JSON, nullable=False)
    # 本词训练实际采用的声调与变调处理说明，**不以字典调机械替代语流读法**
    target_realization = Column(String, nullable=False)
    source_type = Column(String(32), nullable=False)     # textbook|classroom_observation|literature|other
    source_detail = Column(String, nullable=False)       # 可核验出处；未核实页码不得编造
    reference_audio_version = Column(String(64), nullable=False)
    reference_source = Column(String(16), nullable=False)     # tts|human
    reference_generator = Column(String(128), nullable=True)  # 不知道就留空，不猜测
    teacher_hint_version = Column(String(64), nullable=True)
    teacher_hint_text = Column(String, nullable=True)
    review_status = Column(String(16), nullable=False)        # pending|approved|rejected
    reviewed_at = _ts(nullable=True)                          # approved 时必填
    __table_args__ = (UniqueConstraint("lexeme_id", "lexicon_version",
                                       name="uq_lexeme_version"),)


class ResearchAttempt(Base):
    """练习尝试（字典 §7）。一行 = 一次**开始录音**的尝试。

    进入词页但没录音不产生尝试；开始后取消仍保留状态。
    重新录音是新尝试；**上传重试不是新尝试**（同 attempt_id 幂等）。
    """
    __tablename__ = "research_attempts"
    attempt_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    manifest_id = Column(String, ForeignKey("research_manifests.manifest_id"), nullable=False)
    # 前台使用会话：冷启动或后台超过 30 分钟创建新编号。
    # 这是**操作定义**，不等于真实学习课次。
    session_id = Column(String, nullable=False, index=True)
    # fixed_word|free_text|self_test
    # self_test 为本工程扩展（可选自测，纯裸测），字典 v1 未含，见 docs/V2_DECISIONS.md
    task_type = Column(String(16), nullable=False, index=True)
    lexeme_version_id = Column(String, ForeignKey("research_lexemes.lexeme_version_id"),
                               nullable=True)   # free_text 为 NULL，**不存用户原文**
    retry_of_attempt_id = Column(String, nullable=True)
    # 自测记录该词此前已练过的次数（决定 5：接受训练/测试词重叠，改为如实记录）
    prior_practice_count = Column(Integer, nullable=True)
    started_at = _ts(nullable=False)
    received_at = _ts(nullable=False)
    # recording|cancelled|recording_failed|analyzing|analysis_failed|succeeded|interrupted_unknown
    status = Column(String(32), nullable=False, index=True)
    finished_at = _ts(nullable=True)
    recording_duration_ms = Column(Integer, nullable=True)
    analysis_duration_ms = Column(Integer, nullable=True)
    signal_status = Column(String(16), nullable=False)        # unknown|usable|unusable
    # 实际评分指标，定义来自 manifest.scoring_spec。
    # **失败或无有效指标写 NULL**，不写 0 也不写哨兵。
    metric_value = Column(Numeric, nullable=True)
    # 实际阈值判断。无有效评分或未设通过规则为 NULL，
    # **不能把 NULL 当作未通过**。
    passed = Column(Boolean, nullable=True)
    error_code = Column(String(64), nullable=True)
    # 分析结果**首次成功渲染**时间；仅收到服务器结果不能填此项。
    # 后置问卷计数只认 status=succeeded 且本列非空者。
    result_displayed_at = _ts(nullable=True)
    time_quality = Column(String(16), nullable=False)         # valid|suspect|unknown


class ResearchInteractionEvent(Base):
    """操作事件（字典 §8）。event_id 为离线上传的幂等键。"""
    __tablename__ = "research_interaction_events"
    event_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    manifest_id = Column(String, ForeignKey("research_manifests.manifest_id"), nullable=False)
    session_id = Column(String, nullable=False, index=True)
    attempt_id = Column(String, nullable=True)          # 录音前发生的事件可 NULL
    lexeme_version_id = Column(String, nullable=True)
    event_name = Column(String(48), nullable=False, index=True)   # 仅白名单，见 EVENT_NAMES
    occurred_at = _ts(nullable=False)
    received_at = _ts(nullable=False)
    session_elapsed_ms = Column(Integer, nullable=True)
    ui_language = Column(String(32), nullable=False)
    payload = Column(JSON, nullable=False)             # 无参数时为空对象


# 事件白名单（字典 §8）。扩展枚举必须同步递增字典版本。
EVENT_NAMES = {
    "task_opened",            # 练习页**已显示**
    "model_audio_started",    # 示范**实际开始播放**，不是点击
    "learner_audio_started",  # 本人录音实际开始播放；attempt_id 必填
    "feedback_displayed",     # 对应反馈**已渲染**；attempt_id 必填
    "feedback_mode_changed",  # 用户主动切换；from_mode/to_mode
    "history_opened",
    "operation_error",
    "crash_report_received",  # 下次启动取得**确切**崩溃报告
}

# 错误码白名单（字典 §8）
ERROR_CODES = {
    "permission_denied", "no_signal", "signal_unusable", "network_unavailable",
    "timeout", "analysis_engine_error", "playback_error", "render_error",
    "advice_service_error", "unknown",
}


class ResearchAdviceRequest(Base):
    """练习建议请求（字典 §9）。一行 = 用户**点击一次**「练习建议」。

    未点击不自动生成并计作已使用；网络重传复用 request_id。
    """
    __tablename__ = "research_advice_requests"
    request_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    attempt_id = Column(String, ForeignKey("research_attempts.attempt_id"), nullable=False)
    manifest_id = Column(String, ForeignKey("research_manifests.manifest_id"), nullable=False)
    requested_at = _ts(nullable=False)
    received_at = _ts(nullable=False)
    status = Column(String(16), nullable=False)          # pending|succeeded|failed
    # 模板路径同样记录完成时间，**不因此声称是模型生成**
    generated_at = _ts(nullable=True)
    displayed_at = _ts(nullable=True)
    # teacher_hint_only|rule_feedback|ai_generated —— 按**实际执行路径**记录
    source_type = Column(String(32), nullable=False)
    teacher_hint_version = Column(String(64), nullable=True)
    # signal_unusable|overall_metric|verified_syllable_feature|none（none 与其余互斥）
    # ⚠ verified_syllable_feature 的资格判定尚未确认，见 docs/V2_DECISIONS.md 待确认 A。
    #   在确认前**不得**使用该码：现有逐音节 DTW 未经核验。
    evidence_codes = Column(JSON, nullable=False)
    # 仅 signal_status / metric_name / metric_value 及**经验证的** syllable_features；
    # 无证据写空对象。
    evidence_snapshot = Column(JSON, nullable=False)
    model_version = Column(String(128), nullable=True)   # ai_generated 时必填
    prompt_version = Column(String(64), nullable=True)   # ai_generated 时必填
    output_language = Column(String(32), nullable=True)
    output_text = Column(String, nullable=True)          # 不含录音或用户自由输入原文
    error_code = Column(String(64), nullable=True)


class ResearchSurveyInstance(Base):
    """问卷实例（字典 §10）。"""
    __tablename__ = "research_survey_instances"
    survey_instance_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    manifest_id = Column(String, ForeignKey("research_manifests.manifest_id"), nullable=False)
    form_key = Column(String(32), nullable=False)        # background_v1|tone_needs_v1|usability_short_v1
    form_version = Column(String(64), nullable=False)
    language = Column(String(32), nullable=False)        # zh|en|fr|ar（ar = 现代标准阿拉伯语）
    translation_version = Column(String(64), nullable=False)
    invited_at = _ts(nullable=False)
    started_at = _ts(nullable=True)
    submitted_at = _ts(nullable=True)
    # invited|in_progress|deferred|declined|partial|complete
    status = Column(String(16), nullable=False)
    # background|before_first_attempt|after_practice|late_pre
    # 前置问卷若在已开始练习后提交，记 late_pre，**不作为练习前调查**
    timing_class = Column(String(32), nullable=False)
    # 邀请时累计合格次数；背景与前置填 0，**不事后用新增次数覆盖**
    qualifying_attempts_at_invite = Column(Integer, nullable=False)
    trigger_attempt_id = Column(String, nullable=True)
    __table_args__ = (UniqueConstraint("participant_id", "form_key", "form_version",
                                       name="uq_survey_instance"),)


class ResearchSurveyAnswer(Base):
    """问卷回答（字典 §11）。

    POST01—03 的 1–5 分由选项码派生，**不重复写入容易不一致的 score 列**。
    """
    __tablename__ = "research_survey_answers"
    answer_id = Column(String, primary_key=True)
    survey_instance_id = Column(String,
                                ForeignKey("research_survey_instances.survey_instance_id"),
                                nullable=False, index=True)
    question_id = Column(String(16), nullable=False)     # B01–B05 / PRE01–PRE06 / POST01–POST05
    answer_state = Column(String(16), nullable=False)    # answered|skipped|not_answered
    # 已回答的选项题必填；单选恰好 1 项。**禁止存显示标签代替选项码。**
    option_codes = Column(JSON, nullable=True)
    text_value = Column(String, nullable=True)
    answered_at = _ts(nullable=True)
    __table_args__ = (UniqueConstraint("survey_instance_id", "question_id",
                                       name="uq_survey_answer"),)


class ResearchIssueReport(Base):
    """随时报告问题（字典 §12）。入口**始终可用**，不要求先完成 5 次练习。"""
    __tablename__ = "research_issue_reports"
    report_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    manifest_id = Column(String, ForeignKey("research_manifests.manifest_id"), nullable=False)
    attempt_id = Column(String, nullable=True)           # 能明确关联才填
    submitted_at = _ts(nullable=False)
    received_at = _ts(nullable=False)
    category = Column(String(32), nullable=False)
    detail = Column(String(500), nullable=True)          # 提示不填身份信息
    related_event_id = Column(String, nullable=True)     # 系统能确切关联才填


class ResearchRewardEvent(Base):
    """积分事件（字典 §13）。功能上线才启用。

    **只有有效评分通过且满足实际积分规则才记录**；
    不因问卷完成、研究同意或答案倾向给予积分。
    积分**不作为**声调能力或教学效果指标。
    余额与解锁属业务侧，不进研究库。
    """
    __tablename__ = "research_reward_events"
    reward_event_id = Column(String, primary_key=True)
    participant_id = Column(String, ForeignKey("research_participants.participant_id"),
                            nullable=False, index=True)
    attempt_id = Column(String, ForeignKey("research_attempts.attempt_id"), nullable=False)
    reward_rule_version = Column(String(64), nullable=False)
    points_delta = Column(Integer, nullable=False)       # 实际发放的正整数
    awarded_at = _ts(nullable=False)
    __table_args__ = (UniqueConstraint("attempt_id", "reward_rule_version",
                                       name="uq_reward_idempotent"),)
