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
