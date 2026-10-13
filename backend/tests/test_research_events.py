"""研究事件上报的服务端校验与幂等（字典 §8、§15 验收场景）。"""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import research_models as models
from app.database import Base, enforce_sqlite_foreign_keys, get_db
from app.main import app

# StaticPool 必须有：内存 SQLite 每个连接都是独立的空库，
# 不共享连接的话建表和查询会落在不同的库上。
engine = create_engine("sqlite:///:memory:",
                       connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
# 测试库也检查外键：否则插入顺序的问题只会在线上 PostgreSQL 暴露
enforce_sqlite_foreign_keys(engine)
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
# 与 _manifest_row 默认值匹配的客户端版本参数
CLIENT = {"appVersion": "2.0", "build": "1"}


@pytest.fixture(autouse=True)
def clean():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


def _manifest_row(manifest_id="m1", study_id="s1", start=None, end=None, **kw):
    fields = dict(
        manifest_id=manifest_id, study_id=study_id, app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f1", advice_policy_version="a1", survey_version="sv1",
        consent_version="c1", eligibility_version="e1", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=start or NOW - timedelta(days=1),
        collection_end_at=end or NOW + timedelta(days=13), frozen_at=NOW)
    fields.update(kw)
    return models.ResearchManifest(**fields)


def _lexeme_row(version_id="lex-canjia", lexeme_id="canjia", lexicon="lex1"):
    return models.ResearchLexeme(
        lexeme_version_id=version_id, lexeme_id=lexeme_id, lexicon_version=lexicon,
        hanzi="参加", pinyin="cān jiā", citation_tones=[1, 1], source_type="other",
        reference_source="tts", review_status="pending")


def _seed(granted=True, pid="p1"):
    db = TestingSession()
    db.add(_manifest_row())
    db.add(_lexeme_row())
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
    assert r.json() == {"received": 1, "inserted": 1, "duplicates": 0, "rejected": []}


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

def _manifest_only(**kw):
    db = TestingSession()
    db.add(_manifest_row(**kw))
    db.add(_lexeme_row())
    db.commit()
    db.close()


def _register(uid="u1", apple=None):
    """先建业务账号——纳入接口要求账号已存在（需求 R02）。"""
    r = client.post("/student/register",
                    json={"deviceID": uid, "role": "student", "appleUserID": apple})
    assert r.status_code == 200
    return r


def _enroll_body(uid="u1", **kw):
    body = {"internalUserID": uid, "manifestID": "m1", "consentVersion": "c1",
            "consentLanguage": "zh", "consentOccurredAt": NOW.isoformat(),
            "eligibilityStatus": "eligible", "eligibilityVersion": "e1",
            "isTest": True}
    body.update(kw)
    return body


def _enroll(uid="u1", apple=None, **kw):
    _register(uid, apple)
    return client.post("/research/enroll", json=_enroll_body(uid, **kw))


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
                {"questionID": "B03", "state": "answered",
                 "optionCodes": ["hsk2"], "answeredAt": NOW.isoformat()},
                {"questionID": "B04", "state": "skipped"},
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
    assert states == {"B01": "answered", "B02": "answered", "B03": "answered",
                      "B04": "skipped"}
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
    body = _survey(form="tone_needs_v1", version="pre-1.0", status="declined", answers=[])
    body["timingClass"] = "before_first_attempt"
    r = client.post("/research/surveys", json=body)
    assert r.status_code == 200
    db = TestingSession()
    assert db.query(models.ResearchSurveyAnswer).count() == 0
    inst = db.query(models.ResearchSurveyInstance).one()
    assert inst.status == "declined"
    db.close()


# ---------------- 配置下发 ----------------

def test_active_manifest_returned_within_window():
    _manifest_only()
    r = client.get("/research/manifest/active", params=CLIENT)
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
    assert client.get("/research/manifest/active",
                      params={"appVersion": "1.0", "build": "1"}).status_code == 404


def test_window_comes_from_manifest_not_a_fixed_length():
    """窗口由配置显式给出起止时间，不再写死 14 天（需求 R04）。"""
    _manifest_only(start=NOW - timedelta(days=1), end=NOW + timedelta(days=4))
    body = client.get("/research/manifest/active", params=CLIENT).json()
    start = datetime.fromisoformat(body["collectionStartAt"])
    end = datetime.fromisoformat(body["collectionEndAt"])
    assert (end - start) == timedelta(days=5)


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


# ---------------- 时间契约 ----------------
# 历史缺陷：iOS 默认编码把日期发成自 2001 年起的秒数，pydantic 按 1970 解读，
# 差 31 年；返回 200、导出为空、无报错。以下测试确保它以后**大声失败**。

def test_numeric_timestamp_rejected():
    _manifest_only()
    _register("u-num")
    r = client.post("/research/enroll",
                    json=_enroll_body("u-num", consentOccurredAt=811472400))
    assert r.status_code == 422, "数字时间戳必须被拒，否则会被存成 1995 年"


def test_timezone_less_timestamp_rejected():
    _manifest_only()
    _register("u-naive")
    r = client.post("/research/enroll",
                    json=_enroll_body("u-naive", consentOccurredAt="2026-09-19T08:30:00"))
    assert r.status_code == 422


def test_exact_ios_format_stored_correctly():
    """iOS ResearchJSON 实际发出的格式：带三位小数秒与 Z。"""
    _manifest_only()
    _register("u-ios")
    r = client.post("/research/enroll",
                    json=_enroll_body("u-ios", consentOccurredAt="2026-09-19T08:30:00.000Z"))
    assert r.status_code == 200
    db = TestingSession()
    e = db.query(models.ResearchConsentEvent).one()
    assert e.occurred_at.year == 2026, f"存成了 {e.occurred_at}"
    assert (e.occurred_at.hour, e.occurred_at.minute) == (8, 30)
    db.close()


def test_manifest_output_always_has_timezone():
    """客户端解码器要求时区；SQLite 读回会丢 tzinfo，出参必须补上。"""
    _manifest_only()
    body = client.get("/research/manifest/active", params=CLIENT).json()
    for k in ("collectionStartAt", "collectionEndAt"):
        assert body[k].endswith("+00:00") or body[k].endswith("Z"), f"{k} 缺时区：{body[k]}"


# =====================================================================
# 2026-10 研究流程修复（需求 R01–R08）。每条对应一个验收场景。
# =====================================================================

def _withdraw(pid=None, at=None):
    return client.post("/research/withdraw", json={
        "participantID": pid or PID_HOLDER["pid"], "consentVersion": "c1",
        "consentLanguage": "zh", "occurredAt": (at or NOW + timedelta(seconds=1)).isoformat()})


# ---------------- 账号先于纳入（R02 / A02） ----------------

def test_enroll_without_account_rejected():
    """没注册账号就纳入：拒绝，且不产生参与者。此前客户端在登录前就调纳入接口。"""
    _manifest_only()
    r = client.post("/research/enroll", json=_enroll_body("never-registered"))
    assert r.status_code == 409 and "account_required" in r.json()["detail"]
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 0
    db.close()


def test_enroll_requires_eligible_attestation():
    """端侧没判合格（缺失、pending、excluded）一律不纳入——缺失不推定满足（R01 / A05）。"""
    _manifest_only()
    _register("u1")
    for status in (None, "pending", "excluded"):
        r = client.post("/research/enroll", json=_enroll_body("u1", eligibilityStatus=status))
        assert r.status_code == 409, status
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 0
    db.close()


def test_unknown_prior_use_is_enrolled_and_recorded_honestly():
    """使用史未知同样纳入，且**如实记 unknown**，不改写成 new（R01 / A03、A04）。"""
    _manifest_only()
    for uid, status in (("u-unknown", "unknown"), ("u-old", "returning")):
        r = _enroll(uid, priorUseStatus=status)
        assert r.status_code == 200, uid
    db = TestingSession()
    got = sorted(p.prior_use_status for p in db.query(models.ResearchParticipant).all())
    assert got == ["returning", "unknown"]
    db.close()


# ---------------- 同账号跨设备（R08 / A20） ----------------

def test_same_apple_account_on_two_devices_is_one_participant():
    _manifest_only()
    first = _enroll("device-A", apple="apple-1").json()["participantID"]
    second = _enroll("device-B", apple="apple-1")
    assert second.status_code == 200
    assert second.json()["participantID"] == first
    assert second.json()["alreadyEnrolled"] is True
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 1
    # 研究侧存的是账号的随机内部编号，不是设备号，更不是 Apple 标识
    key = db.query(models.ResearchIdentityMap).one().internal_user_id
    assert key not in ("device-A", "device-B", "apple-1")
    db.close()


def test_different_accounts_are_different_participants():
    _manifest_only()
    a = _enroll("device-A", apple="apple-1").json()["participantID"]
    b = _enroll("device-B", apple="apple-2").json()["participantID"]
    assert a != b


def test_second_account_on_the_same_device_is_a_different_participant():
    """同一台设备先后登录两个 Apple 账号：是两位参与者。

    `users` 表一台设备一行，换账号登录是同一行被改写。内部编号若只记在设备行上，
    后来的人会沿用前一个人的编号，被并进同一个研究身份——连对方已填的问卷状态都拿得到。
    """
    _manifest_only()
    first = _enroll("device-A", apple="apple-1").json()["participantID"]
    second = _enroll("device-A", apple="apple-2")
    assert second.status_code == 200
    assert second.json()["participantID"] != first
    assert second.json()["alreadyEnrolled"] is False
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 2
    keys = {r.internal_user_id for r in db.query(models.ResearchIdentityMap).all()}
    assert len(keys) == 2 and "device-A" not in keys
    db.close()


def test_first_account_returning_to_a_shared_device_keeps_its_participant():
    """前一个人再登录回来，还是他原来那位参与者，不会变成第三位。"""
    _manifest_only()
    first = _enroll("device-A", apple="apple-1").json()["participantID"]
    second = _enroll("device-A", apple="apple-2").json()["participantID"]
    again = _enroll("device-A", apple="apple-1")
    assert again.json()["participantID"] == first
    assert again.json()["alreadyEnrolled"] is True
    # 他换到另一台设备也一样
    elsewhere = _enroll("device-B", apple="apple-1")
    assert elsewhere.json()["participantID"] == first
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 2
    assert {first, second} == {p.participant_id for p in db.query(models.ResearchParticipant)}
    db.close()


def test_survey_state_does_not_leak_to_the_next_account_on_the_device():
    """后来的账号上传一份新邀请的问卷，拿到的不是前一个人已提交的那份。"""
    _manifest_only()
    first = _enroll("device-A", apple="apple-1").json()["participantID"]
    done = client.post("/research/surveys", json={
        "participantID": first, "manifestID": "m1", "surveyInstanceID": "inst-first",
        "timingClass": "before_first_attempt", "qualifyingAttemptsAtInvite": 0,
        "invitedAt": NOW.isoformat(),
        "outcome": {"formKey": "tone_needs_v1", "formVersion": "pre-1.0",
                    "translationVersion": "i18n-1.0", "language": "zh",
                    "answers": [{"questionID": "PRE01", "optionCodes": ["often"],
                                 "state": "answered"}],
                    "status": "partial", "startedAt": NOW.isoformat(),
                    "submittedAt": NOW.isoformat()}})
    assert done.status_code == 200, done.text

    second = _enroll("device-A", apple="apple-2").json()["participantID"]
    invited = client.post("/research/surveys", json={
        "participantID": second, "manifestID": "m1", "surveyInstanceID": "inst-second",
        "timingClass": "before_first_attempt", "qualifyingAttemptsAtInvite": 0,
        "invitedAt": NOW.isoformat(),
        "outcome": {"formKey": "tone_needs_v1", "formVersion": "pre-1.0",
                    "translationVersion": "i18n-1.0", "language": "zh",
                    "answers": [], "status": "invited",
                    "startedAt": None, "submittedAt": None}})
    assert invited.status_code == 200, invited.text
    assert invited.json()["status"] == "invited"
    db = TestingSession()
    rows = {r.participant_id: r.status for r in db.query(models.ResearchSurveyInstance)}
    assert rows == {first: "partial", second: "invited"}
    db.close()


def test_account_deletion_forgets_the_apple_link():
    from app import models as business
    _manifest_only()
    _enroll("device-A", apple="apple-1")
    db = TestingSession()
    assert db.query(business.AccountLink).count() == 1
    db.close()
    r = client.delete("/student/account",
                      params={"deviceID": "device-A", "appleUserID": "apple-1"})
    assert r.status_code == 200
    db = TestingSession()
    assert db.query(business.AccountLink).count() == 0
    db.close()


def test_retried_enroll_does_not_duplicate_consent_or_participant():
    """纳入请求超时后重试：不新增参与者，也不追加第二条同意（A06）。"""
    _manifest_only()
    _enroll()
    _enroll()
    db = TestingSession()
    assert db.query(models.ResearchParticipant).count() == 1
    assert db.query(models.ResearchConsentEvent).count() == 1
    db.close()


# ---------------- 同意版本、语言、窗口（R08） ----------------

def test_enroll_rejects_consent_version_not_bound_to_manifest():
    _manifest_only()
    r = _enroll(consentVersion="some-other-text")
    assert r.status_code == 409 and "consent_version_mismatch" in r.json()["detail"]


def test_enroll_rejects_system_locale_as_language():
    """`Locale.current.identifier`（如 en_US）不是 App 内选择的界面语言。"""
    _manifest_only()
    assert _enroll(consentLanguage="en_US").status_code == 400
    assert _enroll("u2", consentLanguage="ar").status_code == 200


def test_enroll_outside_window_rejected():
    _manifest_only(start=NOW - timedelta(days=10), end=NOW - timedelta(days=1))
    r = _enroll()
    assert r.status_code == 409 and "window_closed" in r.json()["detail"]


def test_withdraw_is_idempotent_and_blocks_reenroll():
    """离线退出指令会重试：不重复追加。退出后本轮不重新纳入。"""
    _enrolled()
    assert _withdraw().json()["alreadyWithdrawn"] is False
    assert _withdraw().json()["alreadyWithdrawn"] is True
    db = TestingSession()
    assert db.query(models.ResearchConsentEvent).filter_by(action="withdrawn").count() == 1
    db.close()
    r = client.post("/research/enroll", json=_enroll_body("u1"))
    assert r.status_code == 409 and "withdrawn" in r.json()["detail"]


def test_withdrawal_wins_even_if_client_clock_is_earlier():
    """客户端时钟偏早的退出，仍是「最新」的同意状态——按服务端接收顺序判。"""
    _enrolled()
    _withdraw(at=NOW - timedelta(hours=3))
    assert _post_attempts([_attempt(aid="late")]).status_code == 403


def test_survey_rejected_after_withdrawal():
    """问卷与其它研究写入走同一道门禁——此前问卷接口漏了同意校验（R08 / A21）。"""
    _enrolled()
    _withdraw()
    assert client.post("/research/surveys", json=_survey()).status_code == 403


def test_account_deletion_marks_research_withdrawn():
    """删除账号后，服务端不再接收该参与者的研究上传；研究行不删。"""
    _enrolled()
    assert _post_attempts([_attempt(aid="before")]).json()["inserted"] == 1
    r = client.delete("/student/account", params={"deviceID": "u1"})
    assert r.status_code == 200 and r.json()["researchWithdrawn"] == 1
    assert _post_attempts([_attempt(aid="after")]).status_code == 403
    db = TestingSession()
    assert db.query(models.ResearchAttempt).count() == 1, "既有研究行不随账号删除而删除"
    db.close()


def test_participant_cannot_write_into_another_study():
    _enrolled()
    db = TestingSession()
    db.add(_manifest_row(manifest_id="m-other", study_id="s-other"))
    db.commit()
    db.close()
    r = client.post("/research/attempts", json={
        "participantID": PID_HOLDER["pid"], "manifestID": "m-other",
        "attempts": [_attempt()]})
    assert r.status_code == 409


# ---------------- 问卷：邀请 → 稍后 → 最终（R05 / A11、A12、A19） ----------------

def _post_survey(status, *, instance="inst-1", answers=None, timing="after_practice",
                 n=5, invited=None, submitted=None, form="usability_short_v1"):
    final = status in ("complete", "partial", "declined")
    return client.post("/research/surveys", json={
        "participantID": PID_HOLDER["pid"], "manifestID": "m1",
        "surveyInstanceID": instance, "timingClass": timing,
        "qualifyingAttemptsAtInvite": n,
        "invitedAt": (invited or NOW).isoformat(),
        "outcome": {"formKey": form, "formVersion": "post-1.0",
                    "translationVersion": "i18n-1.0", "language": "fr",
                    "answers": answers or [], "status": status,
                    "startedAt": NOW.isoformat() if status != "invited" else None,
                    "submittedAt": (submitted or NOW).isoformat() if final else None}})


POST_ANSWERS = [{"questionID": "POST01", "state": "answered",
                 "optionCodes": ["agree"], "answeredAt": NOW.isoformat()},
                {"questionID": "POST02", "state": "skipped"}]


def test_deferred_survey_can_later_be_completed():
    """先上报「稍后填写」，之后真的填完：答案必须进来，且还是同一份实例。

    此前接口「已存在即忽略」，deferred 之后的最终答案被直接丢弃。
    """
    _enrolled()
    assert _post_survey("invited").json()["status"] == "invited"
    assert _post_survey("deferred").json()["status"] == "deferred"
    r = _post_survey("partial", answers=POST_ANSWERS)
    assert r.status_code == 200
    assert r.json() == {"surveyInstanceID": "inst-1", "alreadySubmitted": False,
                        "status": "partial", "updated": True}
    db = TestingSession()
    assert db.query(models.ResearchSurveyInstance).count() == 1
    states = {a.question_id: a.answer_state
              for a in db.query(models.ResearchSurveyAnswer).all()}
    assert states == {"POST01": "answered", "POST02": "skipped"}
    db.close()


def test_final_survey_is_not_overwritten_by_late_retransmits():
    """最终提交后：重传幂等；迟到的旧草稿不让答案倒退（A19）。"""
    _enrolled()
    _post_survey("complete", answers=POST_ANSWERS)
    again = _post_survey("complete", answers=[
        {"questionID": "POST01", "state": "answered",
         "optionCodes": ["strongly_disagree"], "answeredAt": NOW.isoformat()}])
    assert again.json()["alreadySubmitted"] is True and again.json()["updated"] is False
    stale = _post_survey("deferred")
    assert stale.json()["status"] == "complete" and stale.json()["updated"] is False
    db = TestingSession()
    a = db.query(models.ResearchSurveyAnswer).filter_by(question_id="POST01").one()
    assert a.option_codes == ["agree"], "已入库的答案被重传改写了"
    assert db.query(models.ResearchSurveyAnswer).count() == 2
    db.close()


def test_status_never_moves_backwards():
    _enrolled()
    _post_survey("deferred")
    r = _post_survey("invited")
    assert r.json()["status"] == "deferred" and r.json()["updated"] is False


def test_invitation_snapshot_survives_later_uploads():
    """邀请时间、邀请时合格次数、语言以首次写入为准，重试不得用当前值替代。"""
    _enrolled()
    invited = NOW - timedelta(hours=2)
    _post_survey("invited", n=5, invited=invited)
    _post_survey("complete", answers=POST_ANSWERS, n=9, invited=NOW)
    db = TestingSession()
    inst = db.query(models.ResearchSurveyInstance).one()
    from app.research_rules import aware
    assert aware(inst.invited_at) == invited
    assert inst.qualifying_attempts_at_invite == 5
    assert inst.language == "fr"
    assert inst.submitted_at is not None and inst.received_at is not None
    db.close()


def test_offline_pre_survey_keeps_its_timing_class():
    """练习前已填完、因离线晚上传的前置问卷仍是前置数据——服务端不按到达时间重分类（A13）。"""
    _enrolled()
    done = NOW - timedelta(hours=5)       # 实际完成时间，远早于到达
    r = _post_survey("complete", form="tone_needs_v1", timing="before_first_attempt",
                     n=0, invited=done, submitted=done,
                     answers=[{"questionID": "PRE01", "state": "answered",
                               "optionCodes": ["often"], "answeredAt": done.isoformat()}])
    assert r.status_code == 200
    db = TestingSession()
    inst = db.query(models.ResearchSurveyInstance).one()
    from app.research_rules import aware
    assert inst.timing_class == "before_first_attempt"
    assert aware(inst.received_at) - aware(inst.submitted_at) > timedelta(hours=4)
    db.close()


def test_survey_timing_class_must_match_form():
    _enrolled()
    assert _post_survey("invited", timing="background").status_code == 400


def test_survey_completed_after_window_rejected():
    """窗口关闭后才完成的问卷是窗口外新产生的数据，不收。"""
    _manifest_only(start=NOW - timedelta(days=5), end=NOW + timedelta(hours=1))
    PID_HOLDER["pid"] = _enroll().json()["participantID"]
    _post_survey("invited")
    r = _post_survey("complete", answers=POST_ANSWERS, submitted=NOW + timedelta(hours=2))
    assert r.status_code == 409 and "outside_window" in r.json()["detail"]


def test_survey_form_version_must_match_manifest_binding():
    _manifest_only(survey_forms={"usability_short_v1": {
        "form_version": "post-1.0", "translation_version": "i18n-1.0"}})
    PID_HOLDER["pid"] = _enroll().json()["participantID"]
    assert _post_survey("invited").status_code == 200
    db = TestingSession()
    db.query(models.ResearchSurveyInstance).delete()
    db.commit()
    db.close()
    bad = client.post("/research/surveys", json={
        "participantID": PID_HOLDER["pid"], "manifestID": "m1", "timingClass": "after_practice",
        "qualifyingAttemptsAtInvite": 5,
        "outcome": {"formKey": "usability_short_v1", "formVersion": "post-9.9",
                    "translationVersion": "i18n-1.0", "language": "fr",
                    "answers": [], "status": "invited"}})
    assert bad.status_code == 409 and "form_version_mismatch" in bad.json()["detail"]


def test_other_text_only_travels_with_an_answered_question():
    _enrolled()
    bad = _post_survey("partial", answers=[
        {"questionID": "POST04", "state": "skipped", "textValue": "残留的补充文字"}])
    assert bad.status_code == 400


def test_background_answers_are_rejudged_on_server():
    """端侧说合格、背景答案却不合格：参与者被改为 excluded，此后不再收研究数据。"""
    _enrolled()
    minor = _survey(answers=[
        {"questionID": "B01", "state": "answered", "optionCodes": ["minor"],
         "answeredAt": NOW.isoformat()},
        {"questionID": "B02", "state": "answered", "optionCodes": ["MA"],
         "answeredAt": NOW.isoformat()},
        {"questionID": "B03", "state": "answered", "optionCodes": ["hsk1"],
         "answeredAt": NOW.isoformat()}])
    assert client.post("/research/surveys", json=minor).status_code == 200
    db = TestingSession()
    p = db.query(models.ResearchParticipant).one()
    assert (p.eligibility_status, p.exclusion_reason) == ("excluded", "age")
    db.close()
    assert _post_attempts([_attempt(aid="x")]).status_code == 403


# ---------------- 窗口按发生时间判（R04 / A22） ----------------

def _windowed(start, end):
    _manifest_only(start=start, end=end)
    db = TestingSession()
    db.add(models.ResearchParticipant(
        participant_id="pw", study_id="s1", enrolled_at=start, eligibility_version="e1",
        eligibility_status="eligible", distribution_channel="app_store",
        recruitment_source="unknown", prior_use_status="unknown",
        prior_use_evidence="insufficient", is_test=True))
    db.add(models.ResearchConsentEvent(
        consent_event_id="cw", participant_id="pw", action="granted",
        consent_version="c1", language="zh", occurred_at=start, received_at=start))
    db.commit()
    db.close()
    PID_HOLDER["pid"] = "pw"


def test_window_start_included_end_excluded():
    start, end = NOW - timedelta(days=2), NOW + timedelta(days=2)
    _windowed(start, end)
    r = _post_attempts([
        _attempt(aid="at-start", startedAt=start.isoformat()),
        _attempt(aid="just-inside", startedAt=(end - timedelta(seconds=1)).isoformat()),
        _attempt(aid="at-end", startedAt=end.isoformat()),
        _attempt(aid="before", startedAt=(start - timedelta(seconds=1)).isoformat()),
    ]).json()
    assert r["inserted"] == 2
    assert sorted(x["id"] for x in r["rejected"]) == ["at-end", "before"]
    assert {x["reason"] for x in r["rejected"]} == {"outside_window"}


def test_offline_data_from_inside_window_accepted_after_window_closed():
    """窗口内合法产生、窗口关闭后才联网补传：收。到达时间另存，不参与窗口判定。"""
    start, end = NOW - timedelta(days=6), NOW - timedelta(days=1)
    _windowed(start, end)
    occurred = end - timedelta(hours=3)
    r = _post_attempts([_attempt(aid="offline", startedAt=occurred.isoformat(),
                                 finishedAt=occurred.isoformat(),
                                 resultDisplayedAt=occurred.isoformat())])
    assert r.status_code == 200 and r.json()["inserted"] == 1
    db = TestingSession()
    from app.research_rules import aware
    row = db.query(models.ResearchAttempt).one()
    assert aware(row.started_at) == occurred
    assert aware(row.received_at) > end, "接收时间应如实记录为窗口关闭之后"
    db.close()
    ev = _event(eid="ev-offline")
    ev["occurredAt"] = occurred.isoformat()
    assert _post([ev], pid="pw").json()["inserted"] == 1


def test_data_produced_after_window_closed_is_rejected_not_stored():
    start, end = NOW - timedelta(days=6), NOW - timedelta(days=1)
    _windowed(start, end)
    r = _post_attempts([_attempt(aid="too-late")]).json()
    assert r["inserted"] == 0 and r["rejected"] == [
        {"id": "too-late", "reason": "outside_window"}]


def test_behaviour_before_consent_is_not_backfilled():
    """同意生效之前的行为不补采（R04 末）。"""
    _enrolled()
    r = _post_attempts([_attempt(
        aid="pre-consent", startedAt=(NOW - timedelta(minutes=30)).isoformat())]).json()
    assert r["rejected"] == [{"id": "pre-consent", "reason": "before_consent"}]


def test_issue_outside_window_rejected():
    start, end = NOW - timedelta(days=6), NOW - timedelta(days=1)
    _windowed(start, end)
    assert client.post("/research/issues", json=_issue(rid="late")).status_code == 409


# ---------------- 尝试：状态与成绩（R07 / A14、A18） ----------------

def test_non_finite_metric_rejected():
    """NaN / Infinity 能通过 JSON 与 float 类型检查，但不是成绩。"""
    _enrolled()
    for literal in ("NaN", "Infinity"):
        raw = ('{"participantID": "%s", "manifestID": "m1", "attempts": [{'
               '"attemptID": "nan-%s", "sessionID": "s", "taskType": "fixed_word",'
               '"lexemeVersionID": "lex-canjia", "startedAt": "%s", "status": "succeeded",'
               '"finishedAt": "%s", "signalStatus": "usable", "metricValue": %s,'
               '"passed": true, "timeQuality": "valid"}]}'
               % (PID_HOLDER["pid"], literal, NOW.isoformat(), NOW.isoformat(), literal))
        r = client.post("/research/attempts", content=raw,
                        headers={"Content-Type": "application/json"})
        assert r.status_code in (400, 422), literal
    db = TestingSession()
    assert db.query(models.ResearchAttempt).count() == 0
    db.close()


def test_sentinel_score_from_legacy_table_rejected():
    _enrolled()
    assert _post_attempts([_attempt(aid="neg", metricValue=-1)]).status_code == 400


def test_cancelled_and_interrupted_are_stored_without_score():
    """取消、未知中断与技术失败分别保存；都没有成绩，也都不是零分。"""
    _enrolled()
    blank = dict(metricValue=None, passed=None, resultDisplayedAt=None)
    r = _post_attempts([
        _attempt(aid="c1", status="cancelled", **blank),
        _attempt(aid="i1", status="interrupted_unknown", finishedAt=None, **blank),
        _attempt(aid="f1", status="recording_failed", errorCode="permission_denied", **blank),
    ])
    assert r.status_code == 200 and r.json()["inserted"] == 3
    db = TestingSession()
    rows = {a.attempt_id: a for a in db.query(models.ResearchAttempt).all()}
    assert {a.status for a in rows.values()} == {
        "cancelled", "interrupted_unknown", "recording_failed"}
    assert all(a.metric_value is None and a.passed is None for a in rows.values())
    db.close()
    bad = _attempt(aid="c2", status="cancelled", metricValue=0.0, passed=False)
    assert _post_attempts([bad]).status_code == 400


def test_self_test_must_not_claim_a_displayed_result():
    _enrolled()
    bad = _attempt(aid="st", task="self_test", lexemeVersionID="lex-canjia")
    assert _post_attempts([bad]).status_code == 400


def test_retry_links_to_previous_attempt():
    _enrolled()
    _post_attempts([_attempt(aid="first")])
    _post_attempts([_attempt(aid="second", retryOfAttemptID="first")])
    db = TestingSession()
    assert db.query(models.ResearchAttempt).filter_by(attempt_id="second").one()\
        .retry_of_attempt_id == "first"
    db.close()


def test_lexeme_version_must_exist_and_belong_to_manifest_lexicon():
    _enrolled()
    db = TestingSession()
    db.add(_lexeme_row(version_id="lex-old", lexeme_id="canjia", lexicon="lex0"))
    db.commit()
    db.close()
    r = _post_attempts([_attempt(aid="ghost", lexemeVersionID="no-such-version"),
                        _attempt(aid="stale", lexemeVersionID="lex-old")]).json()
    assert r["inserted"] == 0
    assert {x["id"]: x["reason"] for x in r["rejected"]} == {
        "ghost": "unknown_lexeme_version", "stale": "lexeme_not_in_manifest_lexicon"}


def test_one_bad_record_does_not_block_the_rest_of_the_batch():
    _enrolled()
    r = _post_attempts([_attempt(aid="good-1"),
                        _attempt(aid="bad", lexemeVersionID="no-such-version"),
                        _attempt(aid="good-2")]).json()
    assert r["inserted"] == 2 and [x["id"] for x in r["rejected"]] == ["bad"]


# ---------------- 事件归属（R07） ----------------

def test_event_cannot_point_at_someone_elses_attempt():
    _manifest_only()
    mine = _enroll("u-mine").json()["participantID"]
    other = _enroll("u-other").json()["participantID"]
    client.post("/research/attempts", json={
        "participantID": other, "manifestID": "m1", "attempts": [_attempt(aid="theirs")]})
    r = client.post("/research/events", json={
        "participantID": mine, "manifestID": "m1",
        "events": [_event(eid="ev1", name="feedback_displayed", attempt="theirs",
                          payload={"mode": "pitch_curve"})]}).json()
    assert r["rejected"] == [{"id": "ev1", "reason": "attempt_owner_mismatch"}]


def test_event_with_system_locale_as_language_rejected():
    _seed()
    e = _event()
    e["uiLanguage"] = "fr-MA"
    assert _post([e]).json()["rejected"] == [{"id": "e1", "reason": "invalid_ui_language"}]


def test_duplicate_ids_inside_one_batch_stored_once():
    _seed()
    r = _post([_event(), _event()]).json()
    assert (r["inserted"], r["duplicates"]) == (1, 1)


# ---------------- 配置下发（R03） ----------------

def test_manifest_not_served_to_clients_that_do_not_state_their_version():
    """旧构建不报版本：一律不下发，研究路径关闭（普通练习不受影响）。"""
    _manifest_only()
    assert client.get("/research/manifest/active").status_code == 404


def test_manifest_not_served_to_mismatched_build():
    _manifest_only()
    assert client.get("/research/manifest/active",
                      params={"appVersion": "2.0", "build": "99"}).status_code == 404
    assert client.get("/research/manifest/active",
                      params={"appVersion": "9.9", "build": "1"}).status_code == 404


def test_manifest_served_to_listed_compatible_build():
    _manifest_only(compatible_builds=["2", "3"])
    assert client.get("/research/manifest/active",
                      params={"appVersion": "2.0", "build": "3"}).status_code == 200


def test_test_manifest_hidden_from_regular_clients():
    """草稿材料只能冻结成测试配置；正式用户永远看不到它（A23）。"""
    _manifest_only(is_test=True)
    assert client.get("/research/manifest/active", params=CLIENT).status_code == 404
    r = client.get("/research/manifest/active", params={**CLIENT, "test": "true"})
    assert r.status_code == 200 and r.json()["isTest"] is True


def test_everyone_enrolled_under_a_test_manifest_is_test_data():
    _manifest_only(is_test=True)
    assert _enroll(isTest=False).status_code == 200
    db = TestingSession()
    assert db.query(models.ResearchParticipant).one().is_test is True
    db.close()


def test_manifest_reports_versions_for_client_self_check():
    _manifest_only(survey_forms={"background_v1": {
        "form_version": "b-1.0", "translation_version": "t-1.0"}})
    body = client.get("/research/manifest/active", params=CLIENT).json()
    assert body["lexiconVersion"] == "lex1" and body["eligibilityVersion"] == "e1"
    assert body["consentVersion"] == "c1" and body["buildNumber"] == "1"
    assert body["surveyForms"]["background_v1"]["form_version"] == "b-1.0"


# ---------------- 练习建议上报（R08） ----------------

def _advice(rid="adv1", attempt="a1", **kw):
    r = {"requestID": rid, "attemptID": attempt, "requestedAt": NOW.isoformat(),
         "status": "succeeded", "generatedAt": NOW.isoformat(),
         "displayedAt": NOW.isoformat(), "sourceType": "rule_feedback",
         "evidenceCodes": ["overall_metric"],
         "evidenceSnapshot": {"metric_name": "normalized_dtw", "metric_value": "0.62"},
         "outputLanguage": "fr", "outputText": "Réessayez."}
    r.update(kw)
    return r


def _post_advice(requests):
    return client.post("/research/advice", json={
        "participantID": PID_HOLDER["pid"], "manifestID": "m1", "requests": requests})


def test_advice_request_stored_and_idempotent():
    _enrolled()
    _post_attempts([_attempt()])
    assert _post_advice([_advice()]).json()["inserted"] == 1
    assert _post_advice([_advice()]).json() == {
        "received": 1, "inserted": 0, "duplicates": 1, "rejected": []}


def test_advice_needs_an_uploaded_attempt_of_the_same_participant():
    _enrolled()
    r = _post_advice([_advice(attempt="not-uploaded-yet")]).json()
    assert r["rejected"] == [{"id": "adv1", "reason": "unknown_attempt"}]


def test_advice_rejects_unverified_evidence_and_ai_source():
    _enrolled()
    _post_attempts([_attempt()])
    assert _post_advice([_advice(evidenceCodes=["verified_syllable_feature"])]).status_code == 400
    assert _post_advice([_advice(sourceType="ai_generated")]).status_code == 400
    assert _post_advice([_advice(evidenceCodes=["none", "overall_metric"])]).status_code == 400
