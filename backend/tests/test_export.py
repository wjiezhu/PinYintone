"""导出口径（字典 §14）。每一条排除规则各造一个参与者，检查导出结果。"""
import csv
import json
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import research_models as m
from app.database import Base
from scripts.export_research import export

NOW = datetime.now(timezone.utc)
engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
Session = sessionmaker(bind=engine)


@pytest.fixture()
def db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    s = Session()
    yield s
    s.close()


def _manifest(db):
    db.add(m.ResearchManifest(
        manifest_id="m1", study_id="s1", app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f", advice_policy_version="a", survey_version="sv",
        consent_version="c", eligibility_version="e", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=NOW - timedelta(days=1),
        collection_end_at=NOW + timedelta(days=13), frozen_at=NOW))


def _person(db, pid, *, is_test=False, prior="new", consent="granted",
            adult="adult", nat="MA", stage="hsk2"):
    db.add(m.ResearchParticipant(
        participant_id=pid, study_id="s1", enrolled_at=NOW, eligibility_version="e",
        eligibility_status="eligible", distribution_channel="app_store",
        recruitment_source="unknown", prior_use_status=prior,
        prior_use_evidence="self_report", is_test=is_test))
    db.add(m.ResearchIdentityMap(participant_id=pid, internal_user_id=f"acct-{pid}",
                                 study_id="s1", created_at=NOW))
    db.add(m.ResearchConsentEvent(consent_event_id=f"c-{pid}", participant_id=pid,
                                  action=consent, consent_version="c", language="zh",
                                  occurred_at=NOW, received_at=NOW))
    iid = f"bg-{pid}"
    db.add(m.ResearchSurveyInstance(
        survey_instance_id=iid, participant_id=pid, manifest_id="m1",
        form_key="background_v1", form_version="b1", language="zh",
        translation_version="t", invited_at=NOW, status="complete",
        timing_class="background", qualifying_attempts_at_invite=0))
    for q, code in (("B01", adult), ("B02", nat), ("B03", stage)):
        state = "answered" if code else "skipped"
        db.add(m.ResearchSurveyAnswer(answer_id=f"{iid}-{q}", survey_instance_id=iid,
                                      question_id=q, answer_state=state,
                                      option_codes=[code] if code else None))


def _attempt(db, aid, pid, when, metric=0.2, passed=True, status="succeeded"):
    db.add(m.ResearchAttempt(
        attempt_id=aid, participant_id=pid, manifest_id="m1", session_id="s",
        task_type="fixed_word", started_at=when, received_at=NOW, status=status,
        finished_at=when, signal_status="usable", metric_value=metric, passed=passed,
        time_quality="valid"))


def _seed(db):
    _manifest(db)
    _person(db, "ok")                              # 合格
    _person(db, "test", is_test=True)              # 测试账户
    _person(db, "old", prior="returning")          # 旧用户
    _person(db, "unknown_prior", prior="unknown")  # 新旧不明——不推定为 new
    _person(db, "withdrew", consent="withdrawn")   # 已撤回
    _person(db, "minor", adult="minor")
    _person(db, "fr", nat="FR")
    _person(db, "hsk5", stage="hsk4_plus")
    _person(db, "skipped_age", adult=None)         # 跳过年龄——不推定成年
    _attempt(db, "a-ok", "ok", NOW)
    _attempt(db, "a-out", "ok", NOW - timedelta(days=5))            # 窗口外
    _attempt(db, "a-fail", "ok", NOW, metric=None, passed=None,
             status="analysis_failed")                             # 失败：空单元格
    _attempt(db, "a-test", "test", NOW)
    db.commit()


def _rows(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def test_only_eligible_participant_exported(db, tmp_path):
    _seed(db)
    meta = export(db, ["m1"], str(tmp_path))
    assert meta["participants_included"] == 1
    assert [r["participant_id"] for r in _rows(tmp_path / "participants.csv")] == ["ok"]
    ex = meta["participants_excluded_by_reason"]
    assert ex["is_test"] == 1
    assert ex["prior_use_not_new"] == 2, "returning 与 unknown 都不得推定为新用户"
    assert ex["consent_not_active"] == 1
    assert ex["age"] == 2, "未成年与跳过年龄都不纳入——缺失不推定满足"
    assert ex["nationality"] == 1
    assert ex["course_stage"] == 1


def test_identity_map_never_exported(db, tmp_path):
    """账号映射是去标识化的关键：导出即破坏去标识（字典 §4）。"""
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    files = {p.name for p in tmp_path.iterdir()}
    assert not any("identity" in f for f in files)
    for f in tmp_path.glob("*.csv"):
        assert "acct-" not in f.read_text(encoding="utf-8"), f"{f.name} 泄露了业务账号键"


def test_out_of_window_and_test_attempts_excluded(db, tmp_path):
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    ids = {r["attempt_id"] for r in _rows(tmp_path / "attempts.csv")}
    assert ids == {"a-ok", "a-fail"}


def test_null_is_empty_cell_and_bool_is_lowercase(db, tmp_path):
    """NULL ≠ 0：失败尝试的 metric_value 必须是空单元格，不能变成 0。"""
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    rows = {r["attempt_id"]: r for r in _rows(tmp_path / "attempts.csv")}
    assert rows["a-fail"]["metric_value"] == ""
    assert rows["a-fail"]["passed"] == ""
    assert rows["a-ok"]["passed"] == "true"


def test_arrays_are_valid_json(db, tmp_path):
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    for r in _rows(tmp_path / "survey_answers.csv"):
        if r["option_codes"]:
            assert isinstance(json.loads(r["option_codes"]), list)


def test_include_test_flag_adds_warning(db, tmp_path):
    _seed(db)
    meta = export(db, ["m1"], str(tmp_path), include_test=True)
    assert meta["participants_excluded_by_reason"].get("is_test") is None
    assert any("测试账户" in w for w in meta["warnings"])


def test_meta_records_rules_and_counts(db, tmp_path):
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    meta = json.loads((tmp_path / "export_meta.json").read_text(encoding="utf-8"))
    for k in ("generated_at", "manifest_ids", "windows", "inclusion_rule",
              "withdrawal_policy", "csv_conventions", "row_counts"):
        assert k in meta


def test_unknown_manifest_aborts(db, tmp_path):
    _seed(db)
    with pytest.raises(SystemExit):
        export(db, ["no_such"], str(tmp_path))
