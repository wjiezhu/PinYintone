"""现场实测改版（2026-10-28）：前测/后测任务、实测事件、录音上传、按配置判纳入。"""
import base64
import hashlib
from datetime import timedelta

import pytest

from app import research_models as models
from app.database import Base
from app.research_rules import judge_background, spec_of
from test_research_events import (NOW, TestingSession, _lexeme_row, _manifest_row, client,
                                  engine)

PROTOCOL = {"lexicon_version": "lex1",
            "test_lexeme_version_ids": ["lex-test"],
            "training_lexeme_version_ids": ["lex-train"],
            "training_valid_attempts_per_word": 3}


@pytest.fixture(autouse=True)
def clean():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


def _seed(*, audio=False, consent="c2", manifest_consent="c2", protocol=PROTOCOL):
    db = TestingSession()
    db.add(_manifest_row(consent_version=manifest_consent, field_protocol_version="field-1.0",
                         field_protocol=protocol, audio_upload=audio))
    db.add(_lexeme_row("lex-test", "hanzi"))
    db.add(_lexeme_row("lex-train", "xianzai"))
    db.add(models.ResearchParticipant(
        participant_id="p1", study_id="s1", enrolled_at=NOW, eligibility_version="e1",
        eligibility_status="eligible", distribution_channel="app_store",
        recruitment_source="unknown", prior_use_status="unknown",
        prior_use_evidence="insufficient", is_test=True, enrolled_manifest_id="m1"))
    db.add(models.ResearchConsentEvent(
        consent_event_id="ce1", participant_id="p1", action="granted",
        consent_version=consent, language="fr", occurred_at=NOW - timedelta(minutes=5),
        received_at=NOW))
    db.commit()
    db.close()


def _attempt(aid="a1", task="pretest", lexeme="lex-test", field="fs1", **kw):
    a = {"attemptID": aid, "sessionID": "sess1", "taskType": task,
         "lexemeVersionID": lexeme, "startedAt": NOW.isoformat(), "status": "succeeded",
         "finishedAt": NOW.isoformat(), "signalStatus": "usable", "metricValue": 0.4,
         "passed": True, "timeQuality": "valid", "fieldSessionID": field}
    a.update(kw)
    return a


def _post_attempts(attempts):
    return client.post("/research/attempts",
                       json={"participantID": "p1", "manifestID": "m1", "attempts": attempts})


def _recording(aid="a1", data=b"\x00\x01fake-aac", **kw):
    body = {"participantID": "p1", "manifestID": "m1", "attemptID": aid,
            "audioFormat": "aac_adts", "sampleRate": 16000, "durationMs": 1200,
            "sha256": hashlib.sha256(data).hexdigest(),
            "audioBase64": base64.b64encode(data).decode()}
    body.update(kw)
    return client.post("/research/recordings", json=body)


# ---- 前测 / 训练 / 后测 ----

def test_pre_and_post_tests_are_stored_with_session_id():
    _seed()
    r = _post_attempts([_attempt("a1", "pretest"),
                        _attempt("a2", "fixed_word", "lex-train"),
                        _attempt("a3", "posttest")])
    assert r.status_code == 200 and r.json()["inserted"] == 3
    db = TestingSession()
    rows = {x.attempt_id: x for x in db.query(models.ResearchAttempt)}
    assert {x.field_session_id for x in rows.values()} == {"fs1"}
    assert rows["a1"].task_type == "pretest" and rows["a3"].task_type == "posttest"
    db.close()


def test_pre_and_post_tests_need_a_field_session():
    _seed()
    assert _post_attempts([_attempt(field=None)]).status_code == 400


def test_bare_tests_never_carry_a_display_time():
    """前测、后测不呈现结果：带了结果显示时间说明客户端给学习者看了反馈。"""
    _seed()
    for task in ("pretest", "posttest"):
        bad = _attempt(task=task, resultDisplayedAt=NOW.isoformat())
        assert _post_attempts([bad]).status_code == 400, task


def test_self_test_cannot_claim_a_field_session():
    _seed()
    assert _post_attempts([_attempt(task="self_test")]).status_code == 400


def test_test_words_and_training_words_cannot_swap():
    """测试段只能是测试词、训练段只能是训练词——否则前后测被「练过的词」污染。"""
    _seed()
    r = _post_attempts([_attempt("a1", "pretest", "lex-train"),
                        _attempt("a2", "fixed_word", "lex-test")])
    assert r.status_code == 200
    reasons = {x["id"]: x["reason"] for x in r.json()["rejected"]}
    assert reasons == {"a1": "lexeme_not_in_field_protocol",
                       "a2": "lexeme_not_in_field_protocol"}


def test_field_attempts_rejected_when_manifest_has_no_protocol():
    _seed(protocol=None)
    r = _post_attempts([_attempt()])
    assert r.json()["rejected"] == [{"id": "a1", "reason": "no_field_protocol"}]


def test_ordinary_practice_unaffected_by_protocol():
    """普通练习（不带流程编号）任何词都照常收。"""
    _seed()
    r = _post_attempts([_attempt("a1", "fixed_word", "lex-test", field=None)])
    assert r.json()["inserted"] == 1


# ---- 实测事件 ----

def _event(name, payload):
    return {"eventID": f"e-{name}", "sessionID": "sess1", "eventName": name,
            "occurredAt": NOW.isoformat(), "uiLanguage": "fr", "payload": payload}


def _post_events(events):
    return client.post("/research/events",
                       json={"participantID": "p1", "manifestID": "m1", "events": events})


def test_field_session_events_accepted():
    _seed()
    r = _post_events([
        _event("field_session_started", {"field_session_id": "fs1",
                                         "protocol_version": "field-1.0"}),
        _event("field_step_completed", {"field_session_id": "fs1", "step": "pretest"}),
        _event("field_session_ended", {"field_session_id": "fs1", "outcome": "abandoned",
                                       "last_step": "training"}),
    ])
    assert r.status_code == 200 and r.json()["inserted"] == 3


@pytest.mark.parametrize("name,payload", [
    ("field_session_started", {"protocol_version": "field-1.0"}),
    ("field_step_completed", {"field_session_id": "fs1", "step": "warmup"}),
    ("field_session_ended", {"field_session_id": "fs1", "outcome": "quit",
                             "last_step": "pretest"}),
])
def test_field_session_events_validated(name, payload):
    _seed()
    assert _post_events([_event(name, payload)]).status_code == 400


# ---- 录音 ----

def test_recording_stored_when_manifest_and_consent_allow():
    _seed(audio=True)
    _post_attempts([_attempt()])
    assert _recording().json() == {"status": "stored"}
    assert _recording().json() == {"status": "duplicate"}, "重传幂等"
    db = TestingSession()
    row = db.query(models.ResearchRecording).one()
    assert row.byte_size == len(b"\x00\x01fake-aac") and row.sample_rate == 16000
    db.close()


def test_recording_refused_when_manifest_does_not_collect_audio():
    """之前的配置写的是「录音不会上传」：一条都不收。"""
    _seed(audio=False)
    _post_attempts([_attempt()])
    assert _recording().status_code == 409


def test_recording_refused_when_participant_consented_to_older_text():
    """只同意过不含录音的文本的人，配置换了也不收他的录音。"""
    _seed(audio=True, consent="c1-old", manifest_consent="c2")
    _post_attempts([_attempt()])
    r = _recording()
    assert r.status_code == 403 and "audio_consent_required" in r.text


def test_recording_checks_integrity_and_format():
    _seed(audio=True)
    _post_attempts([_attempt()])
    assert _recording(sha256="0" * 64).status_code == 400
    assert _recording(sampleRate=44100).status_code == 400, "采样率必须是 16 kHz"
    assert _recording(audioFormat="wav").status_code == 400
    assert _recording(audioFormat="aac_m4a").status_code == 400
    assert _recording(audioBase64="!!!").status_code == 400


def test_recording_needs_its_attempt_first():
    _seed(audio=True)
    r = _recording()
    assert r.status_code == 409 and "attempt_not_uploaded" in r.text


def test_cancelled_attempt_keeps_no_recording():
    _seed(audio=True)
    _post_attempts([_attempt(status="cancelled", metricValue=None, passed=None)])
    assert _recording().status_code == 409


def test_withdrawal_deletes_recordings():
    """声音能认出人：退出研究即删除全部录音。"""
    _seed(audio=True)
    _post_attempts([_attempt()])
    _recording()
    r = client.post("/research/withdraw", json={
        "participantID": "p1", "consentVersion": "c2", "consentLanguage": "fr",
        "occurredAt": NOW.isoformat()})
    assert r.status_code == 200 and r.json()["recordingsDeleted"] == 1
    db = TestingSession()
    assert db.query(models.ResearchRecording).count() == 0
    assert db.query(models.ResearchAttempt).count() == 1, "成绩记录按原规则处理，不随录音删除"
    db.close()


# ---- 纳入规则按配置 ----

class _A:
    def __init__(self, codes):
        self.option_codes, self.answer_state = codes, "answered"


def _answers(nationality):
    return {"B01": _A(["adult"]), "B02": _A([nationality]), "B03": _A(["hsk2"])}


def test_first_round_still_requires_moroccan_nationality():
    """旧配置（第一轮）的人仍按当时的规则判，不被新规则改写。"""
    assert judge_background(_answers("other"), spec_of(None)) == (False, "nationality")
    assert judge_background(_answers("MA"), spec_of(None)) == (True, "")


def test_open_nationality_spec_accepts_any_nationality():
    spec = {"adult_required": True, "nationality_any": [],
            "course_stage_any": ["hsk1", "hsk2", "hsk3"]}
    assert judge_background(_answers("other"), spec) == (True, "")
    assert judge_background(_answers("prefer_not"), spec) == (True, "")
    # 成年与课程阶段照旧
    minor = {**_answers("other"), "B01": _A(["minor"])}
    assert judge_background(minor, spec) == (False, "age")


def test_recordings_export_only_active_consent_and_no_test(tmp_path):
    from scripts.export_recordings import export_recordings
    _seed(audio=True)
    _post_attempts([_attempt()])
    _recording()
    db = TestingSession()
    # 种子里的参与者是测试数据：默认不导出
    assert export_recordings(db, ["m1"], str(tmp_path / "a")) == 0
    assert export_recordings(db, ["m1"], str(tmp_path / "b"), include_test=True) == 1
    assert (tmp_path / "b" / "p1" / "a1.aac").read_bytes() == b"\x00\x01fake-aac"
    db.close()
