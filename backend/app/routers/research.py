"""新版研究数据上报（字段字典 research-data-1.0 + 2026-10 研究流程修复）。

贯穿全文件的约束：

1. **服务端校验不可由客户端校验替代**（字典 §2）。事件名、payload 字段、
   attempt_id 必填性都在这里再验一遍——客户端可能是旧版本，也可能被改过。
2. **幂等靠唯一约束**（字典 §8）。同一编号重传只留一行，不靠客户端保证不重发；
   重传**不覆盖**已入库的有效记录。
3. **所有研究写入走同一道门**（需求 R08）：有效同意、资格、身份、研究归属，
   见 `_write_context`。此前问卷接口漏了同意校验——又一次「每处都记得加条件」失效。
4. **窗口按发生时间判，不按到达时间判**（需求 R04）。窗口内合法产生的离线数据
   可以在窗口关闭后补传；窗口外产生的不收。

错误的两种形态：
- **整批 4xx**：请求本身有问题（未知参与者、无有效同意、格式非法）。客户端不应原样重试。
- **200 + rejected 列表**：这一批里个别记录不该入库（窗口外、同意前、归属不符）。
  其余照常入库。客户端据此丢弃被拒记录，而不是让一条坏记录堵死整个队列。
"""
import math
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import accounts, models, research_models, schemas
from ..database import get_db
from ..research_rules import (UI_LANGUAGES, aware, has_active_consent, judge_background,
                              latest_consent)

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


def _now() -> datetime:
    return datetime.now(timezone.utc)


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


def _write_context(db: Session, participant_id: str, manifest_id: str, *,
                   require_eligible: bool = True):
    """所有研究写入的统一门禁。返回 (参与者, 配置, 同意生效时间)。

    - 参与者与配置都必须存在，且属于**同一研究**——不能拿 A 研究的编号往 B 研究的配置里写。
    - 同意以**服务端**最新一条同意事件为准，不信任客户端的状态快照：
      撤回后离线队列重传也必须被拒（字典 §15）。
    - 资格以服务端记录为准。背景表到达后若复核不合格，participant 会被改成
      excluded，此后的研究写入一律拒绝。
    """
    p = _participant_or_404(db, participant_id)
    m = db.get(research_models.ResearchManifest, manifest_id)
    if m is None:
        raise HTTPException(404, "配置不存在")
    if m.study_id != p.study_id:
        raise HTTPException(409, "参与者与配置不属于同一研究")
    if m.is_test and not p.is_test:
        raise HTTPException(409, "测试配置只接收测试参与者的数据")
    latest = latest_consent(db, participant_id)
    if latest is None or latest.action != "granted":
        raise HTTPException(403, "no_active_consent：该参与者当前无有效同意，拒绝接收研究数据")
    if require_eligible and p.eligibility_status != "eligible":
        raise HTTPException(403, "not_eligible：该参与者不符合纳入条件，拒绝接收研究数据")
    return p, m, aware(latest.occurred_at)


def _window_reason(m: research_models.ResearchManifest, occurred: datetime,
                   consent_at: datetime | None = None) -> str | None:
    """按**发生时间**判窗口。合格返回 None，否则返回拒收原因。

    左闭右开：起点纳入、终点排除（字典 §3）。到达时间不参与判断——
    窗口内产生、窗口关闭后才联网补传的记录是合法的。
    同意生效之前发生的行为不补采（需求 R04 末）。
    """
    t = aware(occurred)
    if t < aware(m.collection_start_at) or t >= aware(m.collection_end_at):
        return "outside_window"
    if consent_at is not None and t < consent_at:
        return "before_consent"
    return None


def _batch_result(received: int, inserted: int, duplicates: int, rejected: list) -> dict:
    return {"received": received, "inserted": inserted,
            "duplicates": duplicates, "rejected": rejected}


@router.post("/research/events")
def upload_events(body: schemas.ResearchEventBatch, db: Session = Depends(get_db)):
    """批量上报操作事件。重复的按幂等丢弃，不更新已有行。"""
    _, manifest, consent_at = _write_context(db, body.participantID, body.manifestID)
    for e in body.events:
        _validate_event(e)

    now = _now()
    inserted = duplicates = 0
    rejected: list[dict] = []
    seen: set[str] = set()
    for e in body.events:
        if e.eventID in seen:
            duplicates += 1
            continue
        seen.add(e.eventID)
        existing = db.get(research_models.ResearchInteractionEvent, e.eventID)
        if existing is not None:
            if existing.participant_id != body.participantID:
                rejected.append({"id": e.eventID, "reason": "id_conflict"})
            else:
                duplicates += 1
            continue
        reason = _window_reason(manifest, e.occurredAt, consent_at)
        if reason is None and e.uiLanguage not in UI_LANGUAGES:
            reason = "invalid_ui_language"
        if reason is None and e.attemptID:
            # 尝试可能还没上传到（顺序由客户端保证，但不强求）；
            # 已经存在却属于别人，则一定是错的。
            att = db.get(research_models.ResearchAttempt, e.attemptID)
            if att is not None and att.participant_id != body.participantID:
                reason = "attempt_owner_mismatch"
        if reason is None and e.lexemeVersionID \
                and db.get(research_models.ResearchLexeme, e.lexemeVersionID) is None:
            reason = "unknown_lexeme_version"
        if reason is not None:
            rejected.append({"id": e.eventID, "reason": reason})
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
    return _batch_result(len(body.events), inserted, duplicates, rejected)


def _identity_for_account(db: Session, account_id: str, study_id: str):
    """按业务账号找既有的研究身份。**只认账号编号，不认设备号。**

    设备号不能当身份用：一台设备可以先后登录两个 Apple 账号，
    按设备号匹配会把后来的人并进前一个人的研究身份里。
    （更早的研究配置下 internal_user_id 存过 device_id；新研究一律用新的 study_id，
    不会与那些旧行相遇。）
    """
    return (db.query(research_models.ResearchIdentityMap)
            .filter(research_models.ResearchIdentityMap.internal_user_id == account_id,
                    research_models.ResearchIdentityMap.study_id == study_id)
            .order_by(research_models.ResearchIdentityMap.created_at.asc())
            .first())


@router.post("/research/enroll", response_model=schemas.ResearchEnrollResponse)
def enroll(body: schemas.ResearchEnrollRequest, db: Session = Depends(get_db)):
    """纳入研究并返回研究编号。

    - **先有账号后纳入**（需求 R02）：internalUserID 必须是已注册的学生账号，
      否则 409。此前客户端在登录之前就调本接口，账号键是空的。
    - **按账号去重，不按设备**：同一账号换设备、重装，返回同一个编号（验收 A20）。
    - **participant_id 由服务端随机生成**，不是 Apple 标识或账号键的派生值（字典 §4）。
    - **只纳入端侧已判合格者**：缺失不推定（需求 R01）。背景表到达后服务端再复核。
    - **同意版本、界面语言须与配置一致**（需求 R08）。
    - **窗口内才能纳入**；窗口关闭后只收补传，不再进新人。
    - **本轮退出后不重新纳入**：导出排除撤回者，若允许退出后重新同意，
      其退出前的资料会被悄悄带回导出。保留策略审定前先堵住。
    """
    manifest = db.get(research_models.ResearchManifest, body.manifestID)
    if manifest is None:
        raise HTTPException(404, "配置不存在")

    user = db.get(models.User, body.internalUserID)
    if user is None or user.role != "student":
        raise HTTPException(409, "account_required：须先注册学生账号再纳入研究")
    account_id = accounts.ensure_account_id(db, user)

    existing = _identity_for_account(db, account_id, manifest.study_id)
    if existing is not None:
        if not has_active_consent(db, existing.participant_id):
            raise HTTPException(409, "withdrawn：已退出本研究，本轮不再重新纳入")
        db.commit()   # 可能刚补写了 account_id
        return schemas.ResearchEnrollResponse(participantID=existing.participant_id,
                                              studyID=manifest.study_id,
                                              alreadyEnrolled=True)

    if body.eligibilityStatus != "eligible":
        raise HTTPException(409, "eligibility_required：只纳入端侧已判定符合条件者")
    if body.eligibilityVersion is not None \
            and body.eligibilityVersion != manifest.eligibility_version:
        raise HTTPException(409, "eligibility_version_mismatch")
    if body.consentVersion != manifest.consent_version:
        raise HTTPException(409, "consent_version_mismatch：同意文本版本与配置不符")
    if body.consentLanguage not in UI_LANGUAGES:
        raise HTTPException(400, f"consentLanguage 须为 App 内界面语言之一：{sorted(UI_LANGUAGES)}")
    now = _now()
    if not (aware(manifest.collection_start_at) <= now < aware(manifest.collection_end_at)):
        raise HTTPException(409, "window_closed：不在采集窗口内，不再纳入新参与者")

    pid = str(uuid.uuid4())
    db.add(research_models.ResearchParticipant(
        participant_id=pid,
        study_id=manifest.study_id,
        enrolled_at=now,
        eligibility_version=manifest.eligibility_version,
        eligibility_status="eligible",
        distribution_channel="app_store",
        recruitment_source=body.recruitmentSource,
        # 如实记录。本轮不以新旧用户作为纳入条件，不为通过检查改写成 new。
        prior_use_status=body.priorUseStatus,
        prior_use_evidence=body.priorUseEvidence,
        # 测试配置下的人一律是测试数据，不看客户端怎么报
        is_test=bool(body.isTest or manifest.is_test),
        enrolled_manifest_id=manifest.manifest_id,
    ))
    # 先把参与者这一行写下去，再写引用它的身份映射与同意记录。
    # 模型里已声明 relationship() 让 ORM 自己按外键顺序插入；这里再显式 flush 一次，
    # 因为纳入是整条链路的入口——顺序错了 PostgreSQL 上直接 500，谁也参加不了。
    db.flush()
    db.add(research_models.ResearchIdentityMap(
        participant_id=pid,
        internal_user_id=account_id,
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
    """退出研究。**追加一条 withdrawn 事件，不改写历史**（字典 §5）。

    - 不受采集窗口限制：窗口关闭后也必须能退出。
    - 幂等：已经是退出状态时不重复追加（离线退出指令会重试）。
    - 退出前资料的处理：正式保留策略审定前，导出**一律排除**退出者（需求 R08）。
      本接口只如实记录状态变更。
    """
    _participant_or_404(db, body.participantID)
    latest = latest_consent(db, body.participantID)
    if latest is not None and latest.action == "withdrawn":
        return {"status": "withdrawn", "alreadyWithdrawn": True}
    db.add(research_models.ResearchConsentEvent(
        consent_event_id=str(uuid.uuid4()),
        participant_id=body.participantID,
        action="withdrawn",
        consent_version=body.consentVersion,
        language=body.consentLanguage,
        occurred_at=body.occurredAt,
        received_at=_now(),
    ))
    db.commit()
    return {"status": "withdrawn", "alreadyWithdrawn": False}


FORM_KEYS = {"background_v1", "tone_needs_v1", "usability_short_v1"}
ANSWER_STATES = {"answered", "skipped", "not_answered"}
SURVEY_STATUSES = {"invited", "in_progress", "deferred", "declined", "partial", "complete"}
# 最终状态：用户已主动结束这份问卷。之后的重传一律幂等，**不覆盖**。
# partial = 用户主动提交但有题未答；declined = 明确不填写。
SURVEY_FINAL = {"declined", "partial", "complete"}
_SURVEY_RANK = {"invited": 0, "in_progress": 1, "deferred": 1,
                "declined": 2, "partial": 2, "complete": 2}
# 字典 §10。late_pre = 前置问卷在已开始练习之后才完成，**不算练习前调查**
TIMING_CLASSES = {"background", "before_first_attempt", "after_practice", "late_pre"}
_FORM_TIMING = {
    "background_v1": {"background"},
    "tone_needs_v1": {"before_first_attempt", "late_pre"},
    "usability_short_v1": {"after_practice"},
}


def _validate_survey(body: schemas.SurveyUploadRequest) -> None:
    o = body.outcome
    if o.formKey not in FORM_KEYS:
        raise HTTPException(400, f"未知表单：{o.formKey}")
    if o.status not in SURVEY_STATUSES:
        raise HTTPException(400, f"未知状态：{o.status}")
    if body.timingClass not in TIMING_CLASSES:
        raise HTTPException(400, f"未知 timing_class：{body.timingClass}")
    if body.timingClass not in _FORM_TIMING[o.formKey]:
        raise HTTPException(400, f"{o.formKey} 不能使用 timing_class={body.timingClass}")
    if o.language not in UI_LANGUAGES:
        raise HTTPException(400, f"language 须为 App 内界面语言之一：{sorted(UI_LANGUAGES)}")
    if body.qualifyingAttemptsAtInvite < 0:
        raise HTTPException(400, "qualifyingAttemptsAtInvite 不得为负")
    # 背景与前置问卷邀请时合格次数应为 0，不得事后用新增次数覆盖（字典 §10）
    if o.formKey in {"background_v1", "tone_needs_v1"} \
            and body.timingClass == "before_first_attempt" \
            and body.qualifyingAttemptsAtInvite != 0:
        raise HTTPException(400, "练习前提交的问卷不得带非零合格次数")
    if o.status in SURVEY_FINAL and o.submittedAt is None:
        raise HTTPException(400, f"{o.status} 必须带 submittedAt")
    seen = set()
    for a in o.answers:
        if a.questionID in seen:
            raise HTTPException(400, f"同一题重复出现：{a.questionID}")
        seen.add(a.questionID)
        if a.state not in ANSWER_STATES:
            raise HTTPException(400, f"未知作答状态：{a.state}")
        if a.state != "answered" and a.optionCodes:
            raise HTTPException(400, "未回答的题不得带选项码")
        if a.state != "answered" and a.textValue:
            raise HTTPException(400, "未回答的题不得带文字")


@router.post("/research/surveys")
def upload_survey(body: schemas.SurveyUploadRequest, db: Session = Depends(get_db)):
    """上报一份问卷的**当前状态**（实例 + 逐题答案）。

    一份问卷在 (participant, form_key, form_version) 上唯一。它会经历
    「已邀请 → 稍后填写 → 最终提交」，每一步客户端都可能上报，也都可能重传：

    - 没有实例：新建。实例编号优先用客户端给的 surveyInstanceID（稳定幂等键）。
    - 已有实例且**尚未最终提交**：更新为新状态，答案整体替换。
      此前这里一律「已存在即忽略」，结果是先存了一条 deferred，
      用户后来真的填完了，答案却进不来。
    - 已有实例且**已最终提交**：幂等返回，不覆盖。旧草稿的迟到重传不会让答案倒退。
    - 状态只能前进：迟到的「已邀请」不会把「稍后填写」改回去。

    **邀请时刻的快照不被后续上传改写**：invited_at、邀请时合格次数、语言、
    译文版本以首次写入为准（需求 R05 末）。

    `timing_class` 由客户端按**发生时间**给出，服务端不按到达时间重新分类：
    练习前已填完、因离线晚到的前置问卷仍是前置数据。
    """
    o = body.outcome
    _validate_survey(body)
    # 背景表本身就是资格的依据，故不要求事先 eligible 之外的条件；其余问卷照常过门禁
    participant, manifest, _ = _write_context(db, body.participantID, body.manifestID)

    if manifest.survey_forms:
        spec = manifest.survey_forms.get(o.formKey)
        if spec is None \
                or spec.get("form_version") != o.formVersion \
                or spec.get("translation_version") != o.translationVersion:
            raise HTTPException(409, "form_version_mismatch：问卷或译文版本与配置绑定的不符")

    existing = (
        db.query(research_models.ResearchSurveyInstance)
        .filter(research_models.ResearchSurveyInstance.participant_id == body.participantID,
                research_models.ResearchSurveyInstance.form_key == o.formKey,
                research_models.ResearchSurveyInstance.form_version == o.formVersion)
        .first()
    )
    if existing is None and body.surveyInstanceID:
        clash = db.get(research_models.ResearchSurveyInstance, body.surveyInstanceID)
        if clash is not None:
            raise HTTPException(409, "id_conflict：该实例编号已被另一份问卷占用")

    def response(inst, *, already: bool, updated: bool):
        return {"surveyInstanceID": inst.survey_instance_id, "alreadySubmitted": already,
                "status": inst.status, "updated": updated}

    if existing is not None:
        if existing.status in SURVEY_FINAL:
            return response(existing, already=True, updated=False)
        if _SURVEY_RANK[o.status] < _SURVEY_RANK[existing.status]:
            return response(existing, already=False, updated=False)

    # 新研究数据的产生须在窗口内：邀请看邀请时间，最终提交看提交时间
    invited_at = body.invitedAt or o.startedAt or o.submittedAt or _now()
    if existing is None and _window_reason(manifest, invited_at) is not None:
        raise HTTPException(409, "outside_window：问卷邀请不在采集窗口内")
    if o.status in SURVEY_FINAL and _window_reason(manifest, o.submittedAt) is not None:
        raise HTTPException(409, "outside_window：问卷不是在采集窗口内完成的")

    now = _now()
    if existing is None:
        existing = research_models.ResearchSurveyInstance(
            survey_instance_id=body.surveyInstanceID or str(uuid.uuid4()),
            participant_id=body.participantID,
            manifest_id=body.manifestID,
            form_key=o.formKey,
            form_version=o.formVersion,
            language=o.language,
            translation_version=o.translationVersion,
            invited_at=invited_at,
            qualifying_attempts_at_invite=body.qualifyingAttemptsAtInvite,
            received_at=now,
        )
        db.add(existing)
    else:
        db.query(research_models.ResearchSurveyAnswer).filter_by(
            survey_instance_id=existing.survey_instance_id).delete(synchronize_session=False)

    existing.started_at = existing.started_at or o.startedAt
    existing.submitted_at = o.submittedAt if o.status in SURVEY_FINAL else None
    existing.status = o.status
    existing.timing_class = body.timingClass
    existing.updated_at = now
    for a in o.answers:
        db.add(research_models.ResearchSurveyAnswer(
            answer_id=str(uuid.uuid4()),
            survey_instance_id=existing.survey_instance_id,
            question_id=a.questionID,
            answer_state=a.state,
            option_codes=a.optionCodes,
            text_value=a.textValue,
            answered_at=a.answeredAt,
        ))

    # 背景表最终提交后按答案复核资格。端侧判过一次，这里再判一次：
    # 不合格的不留在「合格」名下继续收数据。
    if o.formKey == "background_v1" and o.status in SURVEY_FINAL:
        class _A:   # 与 research_rules.judge_background 期望的形状一致
            def __init__(self, a):
                self.option_codes, self.answer_state = a.optionCodes, a.state
        ok, why = judge_background({a.questionID: _A(a) for a in o.answers})
        if not ok:
            participant.eligibility_status = "excluded"
            participant.exclusion_reason = why
    db.commit()
    return response(existing, already=False, updated=True)


@router.get("/research/manifest/active", response_model=schemas.ActiveManifestResponse)
def active_manifest(appVersion: str | None = None, build: str | None = None,
                    test: bool = False, db: Session = Depends(get_db)):
    """返回**与该客户端匹配**的当前生效研究配置；没有就 404。

    客户端不硬编码 manifest_id：配置由研究者冻结后下发。

    不再「窗口内最新的一份给所有人」：配置绑定了具体的 App 版本与构建号
    （评分、词库、问卷都跟着构建走），发给不匹配的客户端等于让它带着别的材料去采集。
    - 不报版本的客户端（旧构建）一律 404——研究路径关闭，普通练习不受影响。
    - 测试配置只发给自报为测试的客户端；正式用户永远看不到测试配置。

    404 时客户端不得纳入任何人，也不得猜一个配置（字典 §3）。
    """
    if not appVersion or not build:
        raise HTTPException(404, "当前无生效的研究配置")
    now = _now()
    rows = (
        db.query(research_models.ResearchManifest)
        .filter(research_models.ResearchManifest.collection_start_at <= now,
                research_models.ResearchManifest.collection_end_at > now)
        .order_by(research_models.ResearchManifest.frozen_at.desc())
        .all()
    )

    def matches(m) -> bool:
        if m.is_test and not test:
            return False
        if m.app_version != appVersion:
            return False
        return build == m.build_number or build in (m.compatible_builds or [])

    candidates = [m for m in rows if matches(m)]
    # 测试客户端优先拿测试配置：同时存在正式与测试配置时，测试账户不应混进正式那份
    if test:
        candidates.sort(key=lambda m: not m.is_test)
    if not candidates:
        raise HTTPException(404, "当前无生效的研究配置")
    m = candidates[0]
    return schemas.ActiveManifestResponse(
        manifestID=m.manifest_id,
        studyID=m.study_id,
        collectionStartAt=m.collection_start_at,
        collectionEndAt=m.collection_end_at,
        postTriggerCount=m.post_trigger_count,
        consentVersion=m.consent_version,
        surveyVersion=m.survey_version,
        rewardRuleVersion=m.reward_rule_version,
        appVersion=m.app_version,
        buildNumber=m.build_number,
        lexiconVersion=m.lexicon_version,
        scoringVersion=m.scoring_version,
        feedbackVersion=m.feedback_version,
        eligibilityVersion=m.eligibility_version,
        surveyForms=m.survey_forms,
        isTest=bool(m.is_test),
    )


ATTEMPT_STATUSES = {"recording", "cancelled", "recording_failed", "analyzing",
                    "analysis_failed", "succeeded", "interrupted_unknown"}
TASK_TYPES = {"fixed_word", "free_text", "self_test"}
SIGNAL_STATUSES = {"unknown", "usable", "unusable"}
TIME_QUALITIES = {"valid", "suspect", "unknown"}
# 这些状态下必须有 finished_at（字典 §7）
STATUSES_REQUIRING_FINISH = {"cancelled", "recording_failed", "analysis_failed", "succeeded"}
# 没有有效成绩的状态：metric / passed 必须为空
STATUSES_WITHOUT_SCORE = {"recording", "cancelled", "recording_failed", "analyzing",
                          "analysis_failed", "interrupted_unknown"}
# 必须说明原因的失败状态。取消与未知中断不是错误，不强求错误码。
STATUSES_REQUIRING_ERROR = {"recording_failed", "analysis_failed"}


def _validate_attempt(a: schemas.ResearchAttemptDTO) -> None:
    if a.status not in ATTEMPT_STATUSES:
        raise HTTPException(400, f"未知状态：{a.status}")
    if a.taskType not in TASK_TYPES:
        raise HTTPException(400, f"未知任务类型：{a.taskType}")
    if a.signalStatus not in SIGNAL_STATUSES:
        raise HTTPException(400, f"未知信号状态：{a.signalStatus}")
    if a.timeQuality not in TIME_QUALITIES:
        raise HTTPException(400, f"未知时间质量：{a.timeQuality}")
    if a.status in STATUSES_REQUIRING_FINISH and a.finishedAt is None:
        raise HTTPException(400, f"{a.status} 必须有 finishedAt")
    if a.taskType in {"fixed_word", "self_test"} and not a.lexemeVersionID:
        raise HTTPException(400, f"{a.taskType} 必须带 lexemeVersionID")
    if a.taskType == "free_text" and a.lexemeVersionID:
        raise HTTPException(400, "free_text 不得带词条编号")
    # 无有效成绩不得填分：字典 §7「失败或无有效指标为 NULL」、
    # 需求 R07「技术失败、取消和未知中断分别保存，无有效成绩用 NULL」
    if a.status in STATUSES_WITHOUT_SCORE:
        if a.metricValue is not None or a.passed is not None:
            raise HTTPException(400, f"{a.status} 不得带 metricValue/passed")
    if a.status in STATUSES_REQUIRING_ERROR and a.errorCode is None:
        raise HTTPException(400, f"{a.status} 必须带 errorCode")
    if a.errorCode is not None and a.errorCode not in ERROR_CODES:
        raise HTTPException(400, f"未定义的错误码：{a.errorCode}")
    if a.metricValue is not None:
        # NaN / Infinity 能通过 JSON 解析与 float 类型检查，但不是成绩
        if not math.isfinite(a.metricValue):
            raise HTTPException(400, "metricValue 必须是有限数值")
        if a.metricValue < 0:
            raise HTTPException(400, "metricValue 为负：疑似旧表哨兵值，无有效指标应为空")
    # 自测不呈现结果，不该带结果显示时间；带了说明客户端把自测当成了有反馈的练习
    if a.taskType == "self_test" and a.resultDisplayedAt is not None:
        raise HTTPException(400, "self_test 不呈现结果，不得带 resultDisplayedAt")
    if a.priorPracticeCount is not None and a.priorPracticeCount < 0:
        raise HTTPException(400, "priorPracticeCount 不得为负")
    for ms in (a.recordingDurationMs, a.analysisDurationMs):
        if ms is not None and ms < 0:
            raise HTTPException(400, "时长不得为负")


@router.post("/research/attempts")
def upload_attempts(body: schemas.ResearchAttemptBatch, db: Session = Depends(get_db)):
    """批量上报练习尝试。

    幂等键是 attempt_id：**上传重试不是新尝试**（字典 §7）。
    已存在的行不覆盖——重复上传只是网络重传，不应改写已入库的结果。
    """
    _, manifest, consent_at = _write_context(db, body.participantID, body.manifestID)
    for a in body.attempts:
        _validate_attempt(a)

    now = _now()
    inserted = duplicates = 0
    rejected: list[dict] = []
    seen: set[str] = set()
    for a in body.attempts:
        if a.attemptID in seen:
            duplicates += 1
            continue
        seen.add(a.attemptID)
        existing = db.get(research_models.ResearchAttempt, a.attemptID)
        if existing is not None:
            if existing.participant_id != body.participantID:
                rejected.append({"id": a.attemptID, "reason": "id_conflict"})
            else:
                duplicates += 1
            continue
        reason = _window_reason(manifest, a.startedAt, consent_at)
        if reason is None and a.lexemeVersionID:
            lex = db.get(research_models.ResearchLexeme, a.lexemeVersionID)
            if lex is None:
                reason = "unknown_lexeme_version"
            elif lex.lexicon_version != manifest.lexicon_version:
                # 词条版本必须属于该配置绑定的词库；否则成绩对应的是别的材料
                reason = "lexeme_not_in_manifest_lexicon"
        if reason is None and a.retryOfAttemptID:
            prev = db.get(research_models.ResearchAttempt, a.retryOfAttemptID)
            if prev is not None and prev.participant_id != body.participantID:
                reason = "retry_owner_mismatch"
        if reason is not None:
            rejected.append({"id": a.attemptID, "reason": reason})
            continue
        db.add(research_models.ResearchAttempt(
            attempt_id=a.attemptID,
            participant_id=body.participantID,
            manifest_id=body.manifestID,
            session_id=a.sessionID,
            task_type=a.taskType,
            lexeme_version_id=a.lexemeVersionID,
            retry_of_attempt_id=a.retryOfAttemptID,
            prior_practice_count=a.priorPracticeCount,
            started_at=a.startedAt,
            received_at=now,
            status=a.status,
            finished_at=a.finishedAt,
            recording_duration_ms=a.recordingDurationMs,
            analysis_duration_ms=a.analysisDurationMs,
            signal_status=a.signalStatus,
            metric_value=a.metricValue,
            passed=a.passed,
            error_code=a.errorCode,
            result_displayed_at=a.resultDisplayedAt,
            time_quality=a.timeQuality,
        ))
        inserted += 1
    db.commit()
    return _batch_result(len(body.attempts), inserted, duplicates, rejected)


ADVICE_STATUSES = {"pending", "succeeded", "failed"}
# 本轮不接 AI：ai_generated 没有模型与提示词版本可填，直接拒收而不是存一个空壳
ADVICE_SOURCE_TYPES = {"teacher_hint_only", "rule_feedback"}
# verified_syllable_feature 的资格未经核验（V2_DECISIONS 第 11 条），本轮不得使用
ADVICE_EVIDENCE_CODES = {"signal_unusable", "overall_metric", "none"}
# gate：平调词走向闸门是否触发。它是明确计算、有阈值依据的**整词**特征
# （V2_DECISIONS 第 11 条的例外），不是未经核验的音节级诊断。字典 1.1 增补。
ADVICE_SNAPSHOT_KEYS = {"signal_status", "metric_name", "metric_value", "gate"}


def _validate_advice(r: schemas.AdviceRequestDTO) -> None:
    if r.status not in ADVICE_STATUSES:
        raise HTTPException(400, f"未知状态：{r.status}")
    if r.sourceType not in ADVICE_SOURCE_TYPES:
        raise HTTPException(400, f"本轮不接收的建议来源：{r.sourceType}")
    extra = set(r.evidenceCodes) - ADVICE_EVIDENCE_CODES
    if extra:
        raise HTTPException(400, f"不允许的证据码：{sorted(extra)}")
    if "none" in r.evidenceCodes and len(r.evidenceCodes) > 1:
        raise HTTPException(400, "证据码 none 与其余互斥")
    extra = set(r.evidenceSnapshot) - ADVICE_SNAPSHOT_KEYS
    if extra:
        raise HTTPException(400, f"不允许的证据快照字段：{sorted(extra)}")
    if r.outputLanguage is not None and r.outputLanguage not in UI_LANGUAGES:
        raise HTTPException(400, "outputLanguage 须为 App 内界面语言之一")
    if r.errorCode is not None and r.errorCode not in ERROR_CODES:
        raise HTTPException(400, f"未定义的错误码：{r.errorCode}")


@router.post("/research/advice")
def upload_advice(body: schemas.AdviceRequestBatch, db: Session = Depends(get_db)):
    """批量上报「练习建议」点击记录（字典 §9）。一行 = 用户点击一次。

    此前只有表、没有接口：客户端记了却从未上传。
    建议必须挂在一次**属于本人、已入库**的尝试上；尝试没到就先不收这条
    （reason=unknown_attempt，客户端下次带着尝试一起再传）。
    """
    _, manifest, consent_at = _write_context(db, body.participantID, body.manifestID)
    for r in body.requests:
        _validate_advice(r)

    now = _now()
    inserted = duplicates = 0
    rejected: list[dict] = []
    seen: set[str] = set()
    for r in body.requests:
        if r.requestID in seen:
            duplicates += 1
            continue
        seen.add(r.requestID)
        existing = db.get(research_models.ResearchAdviceRequest, r.requestID)
        if existing is not None:
            if existing.participant_id != body.participantID:
                rejected.append({"id": r.requestID, "reason": "id_conflict"})
            else:
                duplicates += 1
            continue
        reason = _window_reason(manifest, r.requestedAt, consent_at)
        if reason is None:
            att = db.get(research_models.ResearchAttempt, r.attemptID)
            if att is None:
                reason = "unknown_attempt"
            elif att.participant_id != body.participantID:
                reason = "attempt_owner_mismatch"
        if reason is not None:
            rejected.append({"id": r.requestID, "reason": reason})
            continue
        db.add(research_models.ResearchAdviceRequest(
            request_id=r.requestID,
            participant_id=body.participantID,
            attempt_id=r.attemptID,
            manifest_id=body.manifestID,
            requested_at=r.requestedAt,
            received_at=now,
            status=r.status,
            generated_at=r.generatedAt,
            displayed_at=r.displayedAt,
            source_type=r.sourceType,
            teacher_hint_version=r.teacherHintVersion,
            evidence_codes=r.evidenceCodes,
            evidence_snapshot=r.evidenceSnapshot,
            output_language=r.outputLanguage,
            output_text=r.outputText,
            error_code=r.errorCode,
        ))
        inserted += 1
    db.commit()
    return _batch_result(len(body.requests), inserted, duplicates, rejected)


ISSUE_CATEGORIES = {"cannot_find_action", "recording_failed", "analysis_failed",
                    "app_crashed", "unclear_feedback", "other"}
ISSUE_DETAIL_MAX = 500


@router.post("/research/issues")
def report_issue(body: schemas.IssueReportRequest, db: Session = Depends(get_db)):
    """随时报告问题（字典 §12）。

    - 入口**始终可用**，不要求先完成 5 次练习：未达到使用后问卷阈值就流失的
      用户，只能靠这里留下问题。
    - 用户报告与系统捕获的错误**分别统计**，不自动认定一一对应（问卷 §4 POST04）。
    - 幂等键 report_id：网络重传不产生重复报告。
    - detail 按 Unicode 字符数计上限 500，**不按字节**（字典 §2）——阿拉伯文
      按字节计会把合法长度的文本误判超长。
    - 与其余研究写入同一道门禁，且提交时间须在采集窗口内（需求 R08）。
    """
    _, manifest, consent_at = _write_context(db, body.participantID, body.manifestID)
    if body.category not in ISSUE_CATEGORIES:
        raise HTTPException(400, f"未知问题类别：{body.category}")
    detail = (body.detail or "").strip() or None
    if detail is not None and len(detail) > ISSUE_DETAIL_MAX:
        raise HTTPException(400, f"说明最多 {ISSUE_DETAIL_MAX} 字符")

    existing = db.get(research_models.ResearchIssueReport, body.reportID)
    if existing is not None:
        if existing.participant_id != body.participantID:
            raise HTTPException(409, "id_conflict")
        return {"reportID": body.reportID, "alreadyReceived": True}

    reason = _window_reason(manifest, body.submittedAt, consent_at)
    if reason is not None:
        raise HTTPException(409, f"{reason}：问题报告不是在采集窗口内提交的")
    if body.attemptID:
        att = db.get(research_models.ResearchAttempt, body.attemptID)
        if att is not None and att.participant_id != body.participantID:
            raise HTTPException(409, "attempt_owner_mismatch")

    db.add(research_models.ResearchIssueReport(
        report_id=body.reportID,
        participant_id=body.participantID,
        manifest_id=body.manifestID,
        attempt_id=body.attemptID,
        submitted_at=body.submittedAt,
        received_at=_now(),
        category=body.category,
        detail=detail,
        related_event_id=body.relatedEventID,
    ))
    db.commit()
    return {"reportID": body.reportID, "alreadyReceived": False}
