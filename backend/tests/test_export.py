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
    _person(db, "old", prior="returning")          # 旧用户——本轮同样纳入
    _person(db, "unknown_prior", prior="unknown")  # 新旧不明——本轮同样纳入
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
    # 本轮不以新旧用户作为纳入条件：ok / old / unknown_prior 三人都纳入
    assert meta["participants_included"] == 3
    assert set(r["participant_id"] for r in _rows(tmp_path / "participants.csv")) == \
        {"ok", "old", "unknown_prior"}
    ex = meta["participants_excluded_by_reason"]
    assert ex["is_test"] == 1
    assert "prior_use_not_new" not in ex, "本轮不再按新旧用户排除"
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


def test_prior_use_recorded_honestly_not_rewritten(db, tmp_path):
    """不纳入条件 ≠ 改写数据：prior_use_status 必须保持原值，**不得统一写成 new**。"""
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    by_id = {r["participant_id"]: r for r in _rows(tmp_path / "participants.csv")}
    assert by_id["old"]["prior_use_status"] == "returning"
    assert by_id["unknown_prior"]["prior_use_status"] == "unknown"
    assert by_id["ok"]["prior_use_status"] == "new"


def test_meta_states_prior_use_policy(db, tmp_path):
    """导出说明里必须写明本轮未区分新旧用户，避免被读成「新用户样本」。"""
    _seed(db)
    meta = export(db, ["m1"], str(tmp_path))
    assert "prior_use_policy" in meta
    assert "不以新旧用户作为纳入条件" in meta["prior_use_policy"]
    assert "prior_use_status=new" not in meta["inclusion_rule"]


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


# =====================================================================
# 2026-10：截止时点、研究归属与核对汇总（需求 R04 / R09 / 验收 A26）
# =====================================================================

def _survey(db, pid, form, status, timing, *, n=0, received=None, updated=None):
    db.add(m.ResearchSurveyInstance(
        survey_instance_id=f"{form}-{pid}", participant_id=pid, manifest_id="m1",
        form_key=form, form_version="v1", language="fr", translation_version="t",
        invited_at=NOW, status=status, timing_class=timing,
        qualifying_attempts_at_invite=n,
        submitted_at=NOW if status in ("complete", "partial", "declined") else None,
        received_at=received or NOW, updated_at=updated or received or NOW))


def _event(db, eid, pid, name="feedback_displayed", attempt=None, when=None):
    db.add(m.ResearchInteractionEvent(
        event_id=eid, participant_id=pid, manifest_id="m1", session_id="s",
        attempt_id=attempt, event_name=name, occurred_at=when or NOW, received_at=NOW,
        ui_language="fr", payload={}))


def test_data_arriving_after_cutoff_is_left_out_and_counted(db, tmp_path):
    """定稿之后才到的窗口内补传，不悄悄进入已定稿结果（R04）。"""
    _seed(db)
    cutoff = NOW + timedelta(hours=1)
    db.add(m.ResearchAttempt(
        attempt_id="a-late", participant_id="ok", manifest_id="m1", session_id="s",
        task_type="fixed_word", started_at=NOW, received_at=NOW + timedelta(hours=2),
        status="succeeded", finished_at=NOW, signal_status="usable", metric_value=0.3,
        passed=True, time_quality="valid"))
    db.commit()
    meta = export(db, ["m1"], str(tmp_path), cutoff=cutoff)
    ids = {r["attempt_id"] for r in _rows(tmp_path / "attempts.csv")}
    assert "a-late" not in ids and "a-ok" in ids
    assert meta["arrived_after_cutoff"] == {"attempts": 1}
    saved = json.loads((tmp_path / "export_meta.json").read_text(encoding="utf-8"))
    assert saved["data_cutoff"] == cutoff.isoformat()


def test_survey_finished_after_cutoff_is_left_out(db, tmp_path):
    """截止时还是「稍后填写」、截止后才提交的问卷：导出里不能出现提交后的状态。"""
    _seed(db)
    _survey(db, "ok", "usability_short_v1", "complete", "after_practice", n=5,
            received=NOW, updated=NOW + timedelta(hours=3))
    db.commit()
    meta = export(db, ["m1"], str(tmp_path), cutoff=NOW + timedelta(hours=1))
    forms = {r["form_key"] for r in _rows(tmp_path / "survey_instances.csv")}
    assert "usability_short_v1" not in forms
    assert meta["arrived_after_cutoff"]["survey_instances"] == 1


def test_participants_of_other_studies_are_not_counted_at_all(db, tmp_path):
    """新旧研究分开：别的研究的人既不纳入，也不出现在排除统计里。"""
    _seed(db)
    db.add(m.ResearchParticipant(
        participant_id="other-study", study_id="s-old", enrolled_at=NOW,
        eligibility_version="e", eligibility_status="eligible",
        distribution_channel="app_store", recruitment_source="unknown",
        prior_use_status="unknown", prior_use_evidence="insufficient", is_test=False))
    db.commit()
    meta = export(db, ["m1"], str(tmp_path))
    assert meta["participants_enrolled_in_these_studies"] == 9
    assert meta["participants_included"] == 3
    assert sum(meta["participants_excluded_by_reason"].values()) == 6


def test_server_side_exclusion_is_respected(db, tmp_path):
    """服务端复核后改为 excluded 的参与者不进导出。"""
    _seed(db)
    p = db.get(m.ResearchParticipant, "ok")
    p.eligibility_status, p.exclusion_reason = "excluded", "age"
    db.commit()
    meta = export(db, ["m1"], str(tmp_path))
    assert "ok" not in {r["participant_id"] for r in _rows(tmp_path / "participants.csv")}
    assert meta["participants_excluded_by_reason"]["age"] == 3


def test_background_must_be_finally_submitted(db, tmp_path):
    """只有「已邀请 / 稍后填写」的背景实例不能证明合格——缺失不推定满足。"""
    _seed(db)
    inst = db.get(m.ResearchSurveyInstance, "bg-ok")
    inst.status = "deferred"
    db.commit()
    meta = export(db, ["m1"], str(tmp_path))
    assert meta["participants_excluded_by_reason"]["no_background"] == 1


def test_summary_reconciles_with_the_csv_files(db, tmp_path):
    """核对汇总里的每个数，都能从同一次导出的 CSV 里数出来（A26）。"""
    _seed(db)
    _survey(db, "ok", "tone_needs_v1", "complete", "before_first_attempt")
    _survey(db, "old", "tone_needs_v1", "partial", "late_pre", n=2)
    _survey(db, "unknown_prior", "tone_needs_v1", "declined", "before_first_attempt")
    _survey(db, "ok", "usability_short_v1", "complete", "after_practice", n=5)
    _survey(db, "old", "usability_short_v1", "deferred", "after_practice", n=5)
    _attempt(db, "a-cancel", "old", NOW, metric=None, passed=None, status="cancelled")
    _event(db, "e1", "ok", attempt="a-ok")
    _event(db, "e2", "ok", name="history_opened")
    _event(db, "e3", "ok", attempt="a-out")          # 指向窗口外的尝试
    _event(db, "e-test", "test")                     # 测试账户的事件
    db.commit()

    meta = export(db, ["m1"], str(tmp_path))
    s = json.loads((tmp_path / "summary.json").read_text(encoding="utf-8"))

    assert s["participants"]["included"] == len(_rows(tmp_path / "participants.csv")) == 3
    assert s["surveys"]["background_v1"]["submitted"] == 3

    pre = s["surveys"]["tone_needs_v1"]
    assert pre["by_status"] == {"complete": 1, "partial": 1, "declined": 1}
    assert pre["by_timing_class"] == {"before_first_attempt": 2, "late_pre": 1}
    assert pre["submitted"] == 2 and pre["explicitly_declined"] == 1

    post = s["surveys"]["usability_short_v1"]
    assert post["participants_with_instance"] == 2, "被邀请过的人数"
    assert post["submitted"] == 1 and post["by_status"] == {"complete": 1, "deferred": 1}
    assert post["participants_without_instance"] == 1, "从未达到邀请条件的人"

    attempts = _rows(tmp_path / "attempts.csv")
    assert s["attempts"]["total"] == len(attempts) == 3
    assert s["attempts"]["by_status"] == {
        "succeeded": 1, "analysis_failed": 1, "cancelled": 1}
    assert s["attempts"]["passed"] == {"true": 1, "null": 2}, "无成绩是 null，不是 false"

    events = _rows(tmp_path / "interaction_events.csv")
    assert s["events"]["total_distinct"] == len(events) == 3
    assert s["events"]["referencing_attempt_not_in_export"] == 1
    assert meta["survey_status_counts"] == s["surveys"]


def test_meta_records_commit_cutoff_and_config(db, tmp_path):
    _seed(db)
    export(db, ["m1"], str(tmp_path))
    meta = json.loads((tmp_path / "export_meta.json").read_text(encoding="utf-8"))
    for k in ("backend_commit", "data_cutoff", "manifests", "interpretation_limits",
              "participants_enrolled_in_these_studies", "survey_status_counts"):
        assert k in meta, k
    assert meta["manifests"][0]["app_version"] == "2.0"
    assert meta["manifests"][0]["build_number"] == "1"
    assert any("passed" in x for x in meta["interpretation_limits"])
