"""研究事件上报的服务端校验与幂等（字典 §8、§15 验收场景）。"""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import research_models as models
from app.database import Base, get_db
from app.main import app

# StaticPool 必须有：内存 SQLite 每个连接都是独立的空库，
# 不共享连接的话建表和查询会落在不同的库上。
engine = create_engine("sqlite:///:memory:",
                       connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
TestingSession = sessionmaker(bind=engine)


def _override():
    db = TestingSession()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override
client = TestClient(app)
NOW = datetime.now(timezone.utc)


@pytest.fixture(autouse=True)
def clean():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


def _seed(granted=True, pid="p1"):
    db = TestingSession()
    db.add(models.ResearchManifest(
        manifest_id="m1", study_id="s1", app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f1", advice_policy_version="a1", survey_version="sv1",
        consent_version="c1", eligibility_version="e1", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=NOW - timedelta(days=1),
        collection_end_at=NOW + timedelta(days=13), frozen_at=NOW))
    db.add(models.ResearchParticipant(
        participant_id=pid, study_id="s1", enrolled_at=NOW, eligibility_version="e1",
        eligibility_status="eligible", distribution_channel="app_store",
        recruitment_source="unknown", prior_use_status="new",
        prior_use_evidence="self_report", is_test=True))
    db.add(models.ResearchConsentEvent(
        consent_event_id="ce1", participant_id=pid,
        action="granted" if granted else "withdrawn",
        consent_version="c1", language="zh", occurred_at=NOW, received_at=NOW))
    db.commit()
    db.close()


def _event(eid="e1", name="history_opened", attempt=None, payload=None):
    return {"eventID": eid, "sessionID": "sess1", "attemptID": attempt,
            "eventName": name, "occurredAt": NOW.isoformat(),
            "sessionElapsedMs": 1000, "uiLanguage": "zh", "payload": payload or {}}


def _post(events, pid="p1"):
    return client.post("/research/events",
                       json={"participantID": pid, "manifestID": "m1", "events": events})


def test_accepts_valid_event():
    _seed()
    r = _post([_event()])
    assert r.status_code == 200
    assert r.json() == {"received": 1, "inserted": 1}


def test_duplicate_event_id_inserted_once():
    """验收场景：同一事件重复上传 3 次只有 1 行。"""
    _seed()
    for _ in range(3):
        r = _post([_event()])
        assert r.status_code == 200
    assert r.json()["inserted"] == 0
    db = TestingSession()
    assert db.query(models.ResearchInteractionEvent).count() == 1
    db.close()


def test_withdrawn_consent_rejects_offline_replay():
    """验收场景：离线重传不能绕过同意状态校验。"""
    _seed(granted=False)
    assert _post([_event()]).status_code == 403


def test_unknown_event_name_rejected():
    _seed()
    assert _post([_event(name="totally_made_up")]).status_code == 400


def test_attempt_required_events_rejected_without_attempt():
    _seed()
    for name in ("learner_audio_started", "feedback_displayed", "feedback_mode_changed"):
        assert _post([_event(name=name)]).status_code == 400, name


def test_payload_key_whitelist_enforced():
    _seed()
    assert _post([_event(name="task_opened", payload={"mode": "x"})]).status_code == 400
    assert _post([_event(name="task_opened",
                         payload={"task_type": "fixed_word"})]).status_code == 200


def test_unknown_error_code_rejected():
    _seed()
    bad = _event(name="operation_error",
                 payload={"stage": "recording", "error_code": "oops"})
    assert _post([bad]).status_code == 400
    ok = _event(eid="e2", name="operation_error",
                payload={"stage": "recording", "error_code": "no_signal"})
    assert _post([ok]).status_code == 200


def test_negative_elapsed_rejected():
    _seed()
    e = _event()
    e["sessionElapsedMs"] = -1
    assert _post([e]).status_code == 400


def test_unknown_participant_rejected():
    _seed()
    assert _post([_event()], pid="ghost").status_code == 404


# ---------------- 纳入与撤回 ----------------

def _manifest_only():
    db = TestingSession()
    db.add(models.ResearchManifest(
        manifest_id="m1", study_id="s1", app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f1", advice_policy_version="a1", survey_version="sv1",
        consent_version="c1", eligibility_version="e1", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=NOW - timedelta(days=1),
        collection_end_at=NOW + timedelta(days=13), frozen_at=NOW))
    db.commit()
    db.close()


def _enroll(uid="u1"):
    return client.post("/research/enroll", json={
        "internalUserID": uid, "manifestID": "m1", "consentVersion": "c1",
        "consentLanguage": "zh", "consentOccurredAt": NOW.isoformat(),
        "isTest": True})


def test_enroll_returns_random_id_not_derived_from_account():
    _manifest_only()
    r = _enroll("apple-user-abc")
    assert r.status_code == 200
    pid = r.json()["participantID"]
    assert r.json()["alreadyEnrolled"] is False
    # 研究编号不得由业务账号键派生（字典 §4）
    assert "apple-user-abc" not in pid
    assert len(pid) == 36


def test_enroll_is_idempotent_across_reinstall():
    """换设备或重装后重复纳入，仍是同一研究编号。"""
    _manifest_only()
    first = _enroll().json()["participantID"]
    second = _enroll()
    assert second.json()["participantID"] == first
    assert second.json()["alreadyEnrolled"] is True
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 1
    db.close()


def test_enroll_writes_granted_consent_event():
    _manifest_only()
    pid = _enroll().json()["participantID"]
    db = TestingSession()
    ev = db.query(models.ResearchConsentEvent).filter_by(participant_id=pid).all()
    assert len(ev) == 1 and ev[0].action == "granted"
    db.close()


def test_withdraw_appends_without_rewriting_history():
    """撤回是追加一条 withdrawn，不改写原来的 granted（字典 §5）。"""
    _manifest_only()
    pid = _enroll().json()["participantID"]
    r = client.post("/research/withdraw", json={
        "participantID": pid, "consentVersion": "c1",
        "consentLanguage": "zh", "occurredAt": NOW.isoformat()})
    assert r.status_code == 200
    db = TestingSession()
    actions = [e.action for e in
               db.query(models.ResearchConsentEvent).filter_by(participant_id=pid).all()]
    assert sorted(actions) == ["granted", "withdrawn"], "granted 必须保留"
    db.close()


def test_events_rejected_after_withdrawal():
    """端到端：纳入 → 上报成功 → 撤回 → 同一事件重传被拒。"""
    _manifest_only()
    pid = _enroll().json()["participantID"]
    ok = client.post("/research/events", json={
        "participantID": pid, "manifestID": "m1", "events": [_event()]})
    assert ok.status_code == 200 and ok.json()["inserted"] == 1

    client.post("/research/withdraw", json={
        "participantID": pid, "consentVersion": "c1",
        "consentLanguage": "zh",
        "occurredAt": (NOW + timedelta(seconds=1)).isoformat()})

    replay = client.post("/research/events", json={
        "participantID": pid, "manifestID": "m1", "events": [_event(eid="e2")]})
    assert replay.status_code == 403, "撤回后离线重传必须被拒"


def test_enroll_unknown_manifest_rejected():
    assert _enroll().status_code == 404


# ---------------- 问卷 ----------------

def _survey(form="background_v1", version="background-1.0", status="complete",
            answers=None):
    return {
        "participantID": PID_HOLDER["pid"], "manifestID": "m1",
        "timingClass": "background", "qualifyingAttemptsAtInvite": 0,
        "outcome": {
            "formKey": form, "formVersion": version,
            "translationVersion": "i18n-1.0", "language": "zh",
            "answers": answers if answers is not None else [
                {"questionID": "B01", "state": "answered",
                 "optionCodes": ["adult"], "answeredAt": NOW.isoformat()},
                {"questionID": "B02", "state": "answered",
                 "optionCodes": ["MA"], "answeredAt": NOW.isoformat()},
                {"questionID": "B03", "state": "skipped"},
            ],
            "status": status,
            "startedAt": NOW.isoformat(), "submittedAt": NOW.isoformat()}}


PID_HOLDER = {"pid": ""}


def _enrolled():
    _manifest_only()
    PID_HOLDER["pid"] = _enroll().json()["participantID"]
    return PID_HOLDER["pid"]


def test_survey_stores_three_answer_states_distinctly():
    """跳过 ≠ 没有困难 ≠ 尚未作答（字典 §11）。"""
    _enrolled()
    r = client.post("/research/surveys", json=_survey())
    assert r.status_code == 200
    db = TestingSession()
    states = {a.question_id: a.answer_state
              for a in db.query(models.ResearchSurveyAnswer).all()}
    assert states == {"B01": "answered", "B02": "answered", "B03": "skipped"}
    db.close()


def test_survey_is_idempotent_per_form_version():
    """「稍后填写」恢复原实例，不产生第二份（字典 §10 唯一约束）。"""
    _enrolled()
    first = client.post("/research/surveys", json=_survey()).json()
    second = client.post("/research/surveys", json=_survey()).json()
    assert second["surveyInstanceID"] == first["surveyInstanceID"]
    assert second["alreadySubmitted"] is True
    db = TestingSession()
    assert db.query(models.ResearchSurveyInstance).count() == 1
    db.close()


def test_survey_rejects_unknown_form():
    _enrolled()
    assert client.post("/research/surveys",
                       json=_survey(form="made_up_v9")).status_code == 400


def test_survey_rejects_codes_on_unanswered_question():
    """未回答的题带选项码是自相矛盾的数据，必须拒绝。"""
    _enrolled()
    bad = _survey(answers=[{"questionID": "B01", "state": "skipped",
                            "optionCodes": ["adult"]}])
    assert client.post("/research/surveys", json=bad).status_code == 400


def test_declined_survey_stores_no_fabricated_answers():
    """完全不填记 declined，不生成虚构答案（问卷 §5）。"""
    _enrolled()
    r = client.post("/research/surveys",
                    json=_survey(status="declined", answers=[]))
    assert r.status_code == 200
    db = TestingSession()
    assert db.query(models.ResearchSurveyAnswer).count() == 0
    inst = db.query(models.ResearchSurveyInstance).one()
    assert inst.status == "declined"
    db.close()


# ---------------- 配置下发 ----------------

def test_active_manifest_returned_within_window():
    _manifest_only()
    r = client.get("/research/manifest/active")
    assert r.status_code == 200
    assert r.json()["manifestID"] == "m1"
    assert r.json()["postTriggerCount"] == 5


def test_no_active_manifest_outside_window():
    """窗口外不返回配置——客户端此时不得纳入任何人，也不得猜一个配置。"""
    db = TestingSession()
    db.add(models.ResearchManifest(
        manifest_id="old", study_id="s1", app_version="1.0", build_number="1",
        lexicon_version="lex", scoring_version="sc", scoring_spec={},
        feedback_version="f", advice_policy_version="a", survey_version="sv",
        consent_version="c", eligibility_version="e", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=NOW - timedelta(days=40),
        collection_end_at=NOW - timedelta(days=26), frozen_at=NOW))
    db.commit()
    db.close()
    assert client.get("/research/manifest/active").status_code == 404


def test_window_is_fourteen_days_half_open():
    """统一 14 天窗口，左闭右开（字典 §3）。"""
    _manifest_only()
    body = client.get("/research/manifest/active").json()
    start = datetime.fromisoformat(body["collectionStartAt"])
    end = datetime.fromisoformat(body["collectionEndAt"])
    assert (end - start) == timedelta(days=14)


# ---------------- 练习尝试 ----------------

def _attempt(aid="a1", status="succeeded", task="fixed_word", **kw):
    a = {"attemptID": aid, "sessionID": "sess1", "taskType": task,
         "lexemeVersionID": "lex-canjia" if task == "fixed_word" else None,
         "startedAt": NOW.isoformat(), "status": status,
         "finishedAt": NOW.isoformat(), "signalStatus": "usable",
         "metricValue": 0.21, "passed": True,
         "resultDisplayedAt": NOW.isoformat(), "timeQuality": "valid"}
    a.update(kw)
    return a


def _post_attempts(attempts):
    return client.post("/research/attempts",
                       json={"participantID": PID_HOLDER["pid"],
                             "manifestID": "m1", "attempts": attempts})


def test_attempt_stored_and_idempotent():
    """上传重试不是新尝试（字典 §7）。"""
    _enrolled()
    assert _post_attempts([_attempt()]).json()["inserted"] == 1
    assert _post_attempts([_attempt()]).json()["inserted"] == 0
    db = TestingSession()
    assert db.query(models.ResearchAttempt).count() == 1
    db.close()


def test_failed_attempt_must_not_carry_score():
    """失败记录保留错误类型，**不填零分替代**（需求 §7、字典 §7）。"""
    _enrolled()
    bad = _attempt(aid="a2", status="analysis_failed",
                   metricValue=0.0, passed=False, errorCode="no_signal")
    assert _post_attempts([bad]).status_code == 400

    ok = _attempt(aid="a3", status="analysis_failed",
                  metricValue=None, passed=None, errorCode="no_signal",
                  resultDisplayedAt=None)
    assert _post_attempts([ok]).status_code == 200
    db = TestingSession()
    row = db.query(models.ResearchAttempt).filter_by(attempt_id="a3").one()
    assert row.metric_value is None and row.passed is None
    assert row.error_code == "no_signal"
    db.close()


def test_failed_attempt_requires_error_code():
    _enrolled()
    bad = _attempt(aid="a4", status="recording_failed",
                   metricValue=None, passed=None, errorCode=None,
                   resultDisplayedAt=None)
    assert _post_attempts([bad]).status_code == 400


def test_free_text_must_not_carry_lexeme():
    """free_text 不存词条编号，也不存用户原文（字典 §7）。"""
    _enrolled()
    bad = _attempt(aid="a5", task="free_text", lexemeVersionID="lex-x")
    assert _post_attempts([bad]).status_code == 400


def test_self_test_records_prior_practice_count():
    """自测记该词此前练过几次（决定 5：接受词集重叠，改为如实记录）。"""
    _enrolled()
    a = _attempt(aid="a6", task="self_test", lexemeVersionID="lex-canjia",
                 priorPracticeCount=7, resultDisplayedAt=None)
    assert _post_attempts([a]).status_code == 200
    db = TestingSession()
    assert db.query(models.ResearchAttempt).filter_by(attempt_id="a6").one()\
        .prior_practice_count == 7
    db.close()


def test_finished_status_requires_finished_at():
    _enrolled()
    bad = _attempt(aid="a7", finishedAt=None)
    assert _post_attempts([bad]).status_code == 400


def test_attempts_rejected_after_withdrawal():
    _enrolled()
    client.post("/research/withdraw", json={
        "participantID": PID_HOLDER["pid"], "consentVersion": "c1",
        "consentLanguage": "zh", "occurredAt": (NOW + timedelta(seconds=1)).isoformat()})
    assert _post_attempts([_attempt(aid="a8")]).status_code == 403


# ---------------- 问卷时间定位 ----------------

def _survey_timed(timing, form="tone_needs_v1", n=0, aid=None):
    body = _survey(form=form, version="pre-1.0")
    body["timingClass"] = timing
    body["qualifyingAttemptsAtInvite"] = n
    return body


def test_late_pre_accepted_and_stored():
    """已开始练习后才提交的前置问卷标 late_pre（字典 §10、问卷 §3）。"""
    _enrolled()
    r = client.post("/research/surveys", json=_survey_timed("late_pre", n=3))
    assert r.status_code == 200
    db = TestingSession()
    inst = db.query(models.ResearchSurveyInstance).one()
    assert inst.timing_class == "late_pre"
    assert inst.qualifying_attempts_at_invite == 3
    db.close()


def test_unknown_timing_class_rejected():
    _enrolled()
    assert client.post("/research/surveys",
                       json=_survey_timed("whenever")).status_code == 400


def test_pre_survey_before_practice_must_have_zero_count():
    """前置问卷邀请时合格次数为 0，不得事后用新增次数覆盖（字典 §10）。"""
    _enrolled()
    bad = _survey_timed("before_first_attempt", n=5)
    assert client.post("/research/surveys", json=bad).status_code == 400
    ok = _survey_timed("before_first_attempt", n=0)
    assert client.post("/research/surveys", json=ok).status_code == 200


# ---------------- 报告问题 ----------------

def _issue(rid="r1", category="recording_failed", detail="按了录音没反应"):
    return {"reportID": rid, "participantID": PID_HOLDER["pid"], "manifestID": "m1",
            "submittedAt": NOW.isoformat(), "category": category, "detail": detail}


def test_issue_report_stored_and_idempotent():
    _enrolled()
    r1 = client.post("/research/issues", json=_issue())
    assert r1.status_code == 200 and r1.json()["alreadyReceived"] is False
    r2 = client.post("/research/issues", json=_issue())
    assert r2.json()["alreadyReceived"] is True, "网络重传不得产生重复报告"
    db = TestingSession()
    assert db.query(models.ResearchIssueReport).count() == 1
    db.close()


def test_issue_unknown_category_rejected():
    _enrolled()
    assert client.post("/research/issues",
                       json=_issue(category="made_up")).status_code == 400


def test_issue_detail_limit_counts_characters_not_bytes():
    """500 按 Unicode 字符计，不按字节——阿拉伯文按字节会被误判超长（字典 §2）。"""
    _enrolled()
    arabic_500 = "ب" * 500          # 500 字符，UTF-8 下 1000 字节
    assert client.post("/research/issues",
                       json=_issue(rid="r2", detail=arabic_500)).status_code == 200
    assert client.post("/research/issues",
                       json=_issue(rid="r3", detail="ب" * 501)).status_code == 400


def test_blank_detail_stored_as_null():
    _enrolled()
    client.post("/research/issues", json=_issue(rid="r4", detail="   "))
    db = TestingSession()
    assert db.query(models.ResearchIssueReport).filter_by(report_id="r4").one().detail is None
    db.close()


def test_issue_rejected_after_withdrawal():
    _enrolled()
    client.post("/research/withdraw", json={
        "participantID": PID_HOLDER["pid"], "consentVersion": "c1",
        "consentLanguage": "zh", "occurredAt": (NOW + timedelta(seconds=1)).isoformat()})
    assert client.post("/research/issues", json=_issue(rid="r5")).status_code == 403
