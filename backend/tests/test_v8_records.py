"""记录 schemaVersion 8：旧业务表的走势跨度 / platform 字段，与给旧库补列的迁移。"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import models
from app.database import Base, get_db
from app.main import app
from app.migrations import migrate_v8_columns

engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
TestingSession = sessionmaker(bind=engine)
client = TestClient(app)


def _override():
    db = TestingSession()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(autouse=True)
def isolated_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _override
    try:
        yield
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous


def _session(**kw):
    body = {"id": "s1", "deviceID": "dev", "classCode": None, "role": "student",
            "groupAssignment": "n/a", "lexemeID": "xianzai", "dtwScore": 0.31, "grade": "fail",
            "attemptNumber": 1, "timestamp": "2026-10-20T08:00:00Z", "referenceType": "tts",
            "voicedFrameCount": 88, "qualityFlag": False, "referenceSwitchedDuringAttempt": False,
            "phase": "training", "resultStatus": "valid_result", "schemaVersion": 8,
            "appVersion": "2.1 (21)", "pitchSpanSemitones": 0.4, "platform": "ios"}
    body.update(kw)
    return body


def _row(id="s1"):
    db = TestingSession()
    try:
        return db.get(models.TrainingSession, id)
    finally:
        db.close()


def test_v8_training_session_stores_span_and_platform():
    assert client.post("/api/sync/session", json=_session()).status_code == 200
    r = _row()
    assert r.pitch_span_semitones == pytest.approx(0.4)
    assert r.platform == "ios"
    assert r.schema_version == 8
    # 被幅度闸门拦下的记录：grade = fail 且 dtw ≤ 0.5，且跨度 < 2
    assert r.grade == "fail" and r.dtw_score <= 0.5 and r.pitch_span_semitones < 2.0


def test_technical_retry_never_stores_a_span():
    body = _session(id="t1", dtwScore=-1, grade="n/a", resultStatus="technical_retry",
                    failureReason="insufficient_voiced_frames", pitchSpanSemitones=0.0)
    assert client.post("/api/sync/session", json=body).status_code == 200
    assert _row("t1").pitch_span_semitones is None


def test_old_client_record_is_still_accepted():
    body = _session(id="old", schemaVersion=6, grade="good")
    del body["pitchSpanSemitones"], body["platform"]
    assert client.post("/api/sync/session", json=body).status_code == 200
    r = _row("old")
    assert r.pitch_span_semitones is None and r.platform is None and r.schema_version == 6


def test_aspiration_and_freetext_carry_platform():
    asp = {"id": "a1", "deviceID": "dev", "role": "student", "targetWord": "跑步",
           "triggerRate": 0.7, "passed": True, "timestamp": "2026-10-20T08:00:00Z",
           "phase": "training", "schemaVersion": 8, "appVersion": "2.1 (21)", "platform": "ios"}
    assert client.post("/api/sync/aspiration", json=asp).status_code == 200
    ft = {"id": "f1", "deviceID": "dev", "role": "student", "originalText": "现在",
          "tokenizedWord": "现在", "pinyin": "xiàn zài", "toneSequence": [4, 4],
          "f0Track": [0, 220, 220, 0], "duration": 1.0, "timestamp": "2026-10-20T08:00:00Z",
          "phase": "training", "schemaVersion": 8, "appVersion": "2.1 (21)", "platform": "ios"}
    assert client.post("/api/sync/freetext", json=ft).status_code == 200
    db = TestingSession()
    assert db.get(models.AspirationAttempt, "a1").platform == "ios"
    assert db.get(models.FreeTextRecord, "f1").platform == "ios"
    db.close()


def test_migration_adds_v8_columns_to_an_old_database_and_is_idempotent():
    old = create_engine("sqlite:///:memory:", poolclass=StaticPool)
    with old.begin() as c:
        # v6 时代的表结构（只列迁移相关的几列），里面已有一行旧数据
        c.execute(text("CREATE TABLE training_sessions (id VARCHAR PRIMARY KEY, dtw_score FLOAT, "
                       "schema_version INTEGER)"))
        c.execute(text("INSERT INTO training_sessions VALUES ('old', 0.3, 6)"))
        c.execute(text("CREATE TABLE research_attempts (attempt_id VARCHAR PRIMARY KEY, metric_value NUMERIC)"))
    migrate_v8_columns(old)
    migrate_v8_columns(old)   # 第二次什么也不做
    cols = {c["name"] for c in inspect(old).get_columns("training_sessions")}
    assert {"pitch_span_semitones", "platform"} <= cols
    assert {"pitch_span_semitones", "platform"} <= {c["name"] for c in inspect(old).get_columns("research_attempts")}
    with old.connect() as c:
        row = c.execute(text("SELECT pitch_span_semitones, platform FROM training_sessions")).one()
    assert tuple(row) == (None, None), "旧行不回填猜测值"

