"""新版研究数据上报（字段字典 research-data-1.0）。

两条贯穿全文件的约束：

1. **服务端校验不可由客户端校验替代**（字典 §2）。事件名、payload 字段、
   attempt_id 必填性都在这里再验一遍——客户端可能是旧版本，也可能被改过。
2. **幂等靠唯一约束**（字典 §8）。同一 event_id 重传只留一行，
   不靠客户端保证不重发。
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import research_models, schemas
from ..database import get_db

router = APIRouter(tags=["research"])

# 字典 §8 事件白名单。扩展须同步递增字典版本，否则这里会拒收。
EVENT_NAMES = {
    "task_opened", "model_audio_started", "learner_audio_started",
    "feedback_displayed", "feedback_mode_changed", "history_opened",
    "operation_error", "crash_report_received",
}

# 必须携带 attempt_id 的事件
EVENTS_REQUIRING_ATTEMPT = {
    "learner_audio_started", "feedback_displayed", "feedback_mode_changed",
}

# 各事件允许的 payload 字段
ALLOWED_PAYLOAD_KEYS = {
    "task_opened": {"task_type"},
    "feedback_displayed": {"mode"},
    "feedback_mode_changed": {"from_mode", "to_mode"},
    "operation_error": {"stage", "error_code"},
    "crash_report_received": {"crash_occurred_at"},
    "model_audio_started": set(),
    "learner_audio_started": set(),
    "history_opened": set(),
}

ERROR_CODES = {
    "permission_denied", "no_signal", "signal_unusable", "network_unavailable",
    "timeout", "analysis_engine_error", "playback_error", "render_error",
    "advice_service_error", "unknown",
}


def _validate_event(e: schemas.ResearchEventDTO) -> None:
    if e.eventName not in EVENT_NAMES:
        raise HTTPException(400, f"未知事件名：{e.eventName}")
    if e.eventName in EVENTS_REQUIRING_ATTEMPT and not e.attemptID:
        raise HTTPException(400, f"{e.eventName} 必须携带 attemptID")
    allowed = ALLOWED_PAYLOAD_KEYS[e.eventName]
    extra = set(e.payload or {}) - allowed
    if extra:
        raise HTTPException(400, f"{e.eventName} 不允许的 payload 字段：{sorted(extra)}")
    if e.eventName == "operation_error":
        code = (e.payload or {}).get("error_code")
        if code not in ERROR_CODES:
            raise HTTPException(400, f"未定义的错误码：{code}")
    if e.sessionElapsedMs is not None and e.sessionElapsedMs < 0:
        raise HTTPException(400, "sessionElapsedMs 不得为负")


def _participant_or_404(db: Session, participant_id: str) -> research_models.ResearchParticipant:
    p = db.get(research_models.ResearchParticipant, participant_id)
    if p is None:
        raise HTTPException(404, "参与者不存在")
    return p


@router.post("/research/events")
def upload_events(body: schemas.ResearchEventBatch, db: Session = Depends(get_db)):
    """批量上报操作事件。返回实际新增行数，重复的按幂等丢弃。

    撤回同意后即便离线队列重传也不得入库（字典 §15：
    「离线重传也不能绕过同意状态校验」）——故每批都重新核对同意状态，
    不信任客户端上报时的状态快照。
    """
    participant = _participant_or_404(db, body.participantID)

    # 同意状态以**服务端**的最新一条同意事件为准
    latest = (
        db.query(research_models.ResearchConsentEvent)
        .filter(research_models.ResearchConsentEvent.participant_id == body.participantID)
        .order_by(research_models.ResearchConsentEvent.occurred_at.desc())
        .first()
    )
    if latest is None or latest.action != "granted":
        raise HTTPException(403, "该参与者当前无有效同意，拒绝接收研究事件")

    manifest = db.get(research_models.ResearchManifest, body.manifestID)
    if manifest is None:
        raise HTTPException(404, "配置不存在")

    now = datetime.now(timezone.utc)
    inserted = 0
    for e in body.events:
        _validate_event(e)
        # 幂等：已存在同一 event_id 则跳过，不更新已有行
        if db.get(research_models.ResearchInteractionEvent, e.eventID) is not None:
            continue
        db.add(research_models.ResearchInteractionEvent(
            event_id=e.eventID,
            participant_id=body.participantID,
            manifest_id=body.manifestID,
            session_id=e.sessionID,
            attempt_id=e.attemptID,
            lexeme_version_id=e.lexemeVersionID,
            event_name=e.eventName,
            occurred_at=e.occurredAt,
            received_at=now,
            session_elapsed_ms=e.sessionElapsedMs,
            ui_language=e.uiLanguage,
            payload=e.payload or {},
        ))
        inserted += 1
    db.commit()
    return {"received": len(body.events), "inserted": inserted}


@router.post("/research/enroll", response_model=schemas.ResearchEnrollResponse)
def enroll(body: schemas.ResearchEnrollRequest, db: Session = Depends(get_db)):
    """纳入研究并返回研究编号。

    三条约束：
    - **participant_id 由服务端随机生成**，绝不是 Apple 标识或业务账号键的派生值
      （字典 §4：「不得直接使用 Apple 标识作研究编号」）。
    - **幂等**：同一 (internal_user_id, study_id) 重复调用返回同一编号，
      靠 research_identity_map 的唯一约束保证，换设备/重装不会产生第二个编号。
    - **同意先于纳入**：本接口同时落一条 granted 同意事件；
      未同意不应调用本接口（字典 §5：拒绝研究时不必创建参与者）。
    """
    manifest = db.get(research_models.ResearchManifest, body.manifestID)
    if manifest is None:
        raise HTTPException(404, "配置不存在")

    existing = (
        db.query(research_models.ResearchIdentityMap)
        .filter(research_models.ResearchIdentityMap.internal_user_id == body.internalUserID,
                research_models.ResearchIdentityMap.study_id == manifest.study_id)
        .first()
    )
    if existing is not None:
        return schemas.ResearchEnrollResponse(participantID=existing.participant_id,
                                              studyID=manifest.study_id,
                                              alreadyEnrolled=True)

    now = datetime.now(timezone.utc)
    pid = str(uuid.uuid4())
    db.add(research_models.ResearchParticipant(
        participant_id=pid,
        study_id=manifest.study_id,
        enrolled_at=now,
        eligibility_version=manifest.eligibility_version,
        # 首次写入必须 eligible（字典 §4）；端侧已做资格门禁，
        # 不合格者不应走到这里
        eligibility_status="eligible",
        distribution_channel="app_store",
        recruitment_source=body.recruitmentSource,
        prior_use_status=body.priorUseStatus,
        prior_use_evidence=body.priorUseEvidence,
        is_test=body.isTest,
    ))
    db.add(research_models.ResearchIdentityMap(
        participant_id=pid,
        internal_user_id=body.internalUserID,
        study_id=manifest.study_id,
        created_at=now,
    ))
    db.add(research_models.ResearchConsentEvent(
        consent_event_id=str(uuid.uuid4()),
        participant_id=pid,
        action="granted",
        consent_version=body.consentVersion,
        language=body.consentLanguage,
        occurred_at=body.consentOccurredAt,
        received_at=now,
    ))
    db.commit()
    return schemas.ResearchEnrollResponse(participantID=pid,
                                          studyID=manifest.study_id,
                                          alreadyEnrolled=False)


@router.post("/research/withdraw")
def withdraw(body: schemas.ResearchWithdrawRequest, db: Session = Depends(get_db)):
    """撤回同意。**追加一条 withdrawn 事件，不改写历史**（字典 §5）。

    撤回后停止后续采集；退出前已收集的资料按研究者已确认的意向保留
    （字典 §5：该意向仍须核对学校要求后在知情说明中写明，
    本接口只负责如实记录状态变更，不代表已获准执行任何保留策略）。
    """
    _participant_or_404(db, body.participantID)
    now = datetime.now(timezone.utc)
    db.add(research_models.ResearchConsentEvent(
        consent_event_id=str(uuid.uuid4()),
        participant_id=body.participantID,
        action="withdrawn",
        consent_version=body.consentVersion,
        language=body.consentLanguage,
        occurred_at=body.occurredAt,
        received_at=now,
    ))
    db.commit()
    return {"status": "withdrawn"}


FORM_KEYS = {"background_v1", "tone_needs_v1", "usability_short_v1"}
ANSWER_STATES = {"answered", "skipped", "not_answered"}
SURVEY_STATUSES = {"invited", "in_progress", "deferred", "declined", "partial", "complete"}


@router.post("/research/surveys")
def upload_survey(body: schemas.SurveyUploadRequest, db: Session = Depends(get_db)):
    """上报一份问卷（实例 + 逐题答案）。

    - **(participant, form_key, form_version) 唯一**（字典 §10）：
      「稍后填写」恢复原实例，不产生第二份；重复提交返回原实例编号。
    - `answer_state` 三态分别保存：跳过 ≠ 「没有困难」≠ 尚未作答（字典 §11）。
    - **不接受未定义的表单或状态**——服务端按冻结版本校验。
    """
    _participant_or_404(db, body.participantID)
    o = body.outcome
    if o.formKey not in FORM_KEYS:
        raise HTTPException(400, f"未知表单：{o.formKey}")
    if o.status not in SURVEY_STATUSES:
        raise HTTPException(400, f"未知状态：{o.status}")
    for a in o.answers:
        if a.state not in ANSWER_STATES:
            raise HTTPException(400, f"未知作答状态：{a.state}")
        if a.state != "answered" and a.optionCodes:
            raise HTTPException(400, "未回答的题不得带选项码")

    existing = (
        db.query(research_models.ResearchSurveyInstance)
        .filter(research_models.ResearchSurveyInstance.participant_id == body.participantID,
                research_models.ResearchSurveyInstance.form_key == o.formKey,
                research_models.ResearchSurveyInstance.form_version == o.formVersion)
        .first()
    )
    if existing is not None:
        return {"surveyInstanceID": existing.survey_instance_id, "alreadySubmitted": True}

    now = datetime.now(timezone.utc)
    instance_id = str(uuid.uuid4())
    db.add(research_models.ResearchSurveyInstance(
        survey_instance_id=instance_id,
        participant_id=body.participantID,
        manifest_id=body.manifestID,
        form_key=o.formKey,
        form_version=o.formVersion,
        language=o.language,
        translation_version=o.translationVersion,
        invited_at=o.startedAt or now,
        started_at=o.startedAt,
        submitted_at=o.submittedAt,
        status=o.status,
        timing_class="background" if o.formKey == "background_v1" else "after_practice",
        qualifying_attempts_at_invite=0,
    ))
    for a in o.answers:
        db.add(research_models.ResearchSurveyAnswer(
            answer_id=str(uuid.uuid4()),
            survey_instance_id=instance_id,
            question_id=a.questionID,
            answer_state=a.state,
            option_codes=a.optionCodes,
            text_value=a.textValue,
            answered_at=a.answeredAt,
        ))
    db.commit()
    return {"surveyInstanceID": instance_id, "alreadySubmitted": False}


@router.get("/research/manifest/active", response_model=schemas.ActiveManifestResponse)
def active_manifest(db: Session = Depends(get_db)):
    """返回当前生效的研究配置。

    客户端**不硬编码** manifest_id：配置由研究者冻结后下发，
    硬编码会在换配置时把数据归到旧配置下。
    没有处在窗口内的配置时返回 404——此时客户端不应纳入任何人，
    也不应猜一个配置（字典 §3：不同配置不能直接混算分数）。
    """
    now = datetime.now(timezone.utc)
    m = (
        db.query(research_models.ResearchManifest)
        .filter(research_models.ResearchManifest.collection_start_at <= now,
                research_models.ResearchManifest.collection_end_at > now)
        .order_by(research_models.ResearchManifest.frozen_at.desc())
        .first()
    )
    if m is None:
        raise HTTPException(404, "当前无生效的研究配置")
    return schemas.ActiveManifestResponse(
        manifestID=m.manifest_id,
        studyID=m.study_id,
        collectionStartAt=m.collection_start_at,
        collectionEndAt=m.collection_end_at,
        postTriggerCount=m.post_trigger_count,
        consentVersion=m.consent_version,
        surveyVersion=m.survey_version,
    )
