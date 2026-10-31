"""研究配置冻结脚本（需求 R03 / R04）。"""
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import research_models as m
from app.database import Base, enforce_sqlite_foreign_keys
from scripts.seed_manifest import (ManifestError, build_manifest, formal_blockers,
                                   load_survey_forms, parse_time)

engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
# 测试库也检查外键：否则插入顺序的问题只会在线上 PostgreSQL 暴露
enforce_sqlite_foreign_keys(engine)
Session = sessionmaker(bind=engine)
START = datetime(2026, 10, 20, 7, tzinfo=timezone.utc)
FORMS = {k: {"form_version": f"{k}-1.0", "translation_version": "i18n-1.0"}
         for k in ("background_v1", "tone_needs_v1", "usability_short_v1")}


@pytest.fixture()
def db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    s = Session()
    yield s
    s.close()


def _lexeme(db, lid, status="approved", lexicon="lex-1.0"):
    db.add(m.ResearchLexeme(
        lexeme_version_id=f"v-{lid}", lexeme_id=lid, lexicon_version=lexicon,
        hanzi="参加", pinyin="cān jiā", citation_tones=[1, 1], source_type="textbook",
        reference_source="tts", review_status=status))
    db.commit()


def _build(db, **kw):
    args = dict(study_id="s1", app_version="1.0", build_number="17",
                lexicon_version="lex-1.0", scoring_version="scoring-v5",
                feedback_version="fb-1.0", advice_policy_version="advice-1.0",
                survey_version="survey-1.0", consent_version="consent-1.0",
                eligibility_version="eligibility-2.0",
                collection_start=START, collection_end=START + timedelta(days=5),
                survey_forms=FORMS)
    args.update(kw)
    return build_manifest(db, **args)


def test_window_is_whatever_the_researcher_states(db):
    """起止时间显式给出，不再按固定 14 天推算终点。"""
    _lexeme(db, "canjia")
    man = _build(db, collection_end=START + timedelta(days=4, hours=6))
    assert man.collection_end_at - man.collection_start_at == timedelta(days=4, hours=6)


def test_end_must_be_after_start(db):
    _lexeme(db, "canjia")
    for end in (START, START - timedelta(hours=1)):
        with pytest.raises(ManifestError, match="晚于"):
            _build(db, collection_end=end)


def test_times_must_carry_a_timezone_and_are_stored_as_utc():
    with pytest.raises(ManifestError, match="时区"):
        parse_time("2026-10-20T08:00:00", "--collection-start")
    t = parse_time("2026-10-20T08:00:00+01:00", "--collection-start")
    assert t == START and t.utcoffset() == timedelta(0)


def test_new_manifests_do_not_require_new_users(db):
    _lexeme(db, "canjia")
    assert _build(db).eligibility_spec["new_user_required"] is False


def test_draft_materials_cannot_become_a_formal_manifest(db):
    """未审定的同意文本、draft 问卷、未核对词条：只能冻结成测试配置（R03 / A23）。"""
    _lexeme(db, "canjia", status="approved")
    _lexeme(db, "xiuxi", status="pending")
    draft_forms = {k: {"form_version": f"{k}-1.0-draft",
                       "translation_version": "research-survey-i18n-1.0-draft"}
                   for k in FORMS}
    with pytest.raises(ManifestError) as e:
        _build(db, consent_version="consent-1.0-unpublished", survey_forms=draft_forms)
    msg = str(e.value)
    assert "consent-1.0-unpublished" in msg
    assert "xiuxi" in msg and "1/2" in msg
    assert "background_v1" in msg

    test_manifest = _build(db, consent_version="consent-1.0-unpublished",
                           survey_forms=draft_forms, is_test=True)
    assert test_manifest.is_test is True


def test_formal_manifest_needs_the_lexicon_to_be_seeded(db):
    problems = formal_blockers(db, consent_version="consent-1.0",
                               eligibility_version="eligibility-2.0",
                               lexicon_version="lex-1.0", survey_forms=FORMS)
    assert any("尚未入库" in p for p in problems)


def test_fully_reviewed_materials_can_be_frozen_as_formal(db):
    _lexeme(db, "canjia")
    man = _build(db, compatible_builds=["18"])
    assert man.is_test is False
    assert man.compatible_builds == ["18"]
    assert man.survey_forms == FORMS


def test_bundled_survey_versions_are_read_from_the_app_resources():
    """配置绑定的是 App 实际携带的那一版问卷，从同一份 JSON 读。"""
    import os
    from scripts.seed_manifest import DEFAULT_SURVEY_DIR
    assert os.path.isdir(DEFAULT_SURVEY_DIR)
    forms = load_survey_forms(DEFAULT_SURVEY_DIR)
    assert set(forms) == {"background_v1", "tone_needs_v1", "usability_short_v1"}
    assert all(v["form_version"] and v["translation_version"] for v in forms.values())


def test_shipped_materials_are_final(db):
    """研究者 2026-10-14 审定后，仓库里随 App 发布的问卷都是定稿版本，
    可以冻结成正式配置（此前这里是「仍是草稿、冻结不出来」的护栏）。

    以后若有人把问卷改回草稿或改了题目却没改版本号，这里会先失败。
    """
    from scripts.seed_manifest import DEFAULT_SURVEY_DIR
    forms = load_survey_forms(DEFAULT_SURVEY_DIR)
    for key, spec in forms.items():
        assert "draft" not in spec["form_version"], key
        assert "draft" not in spec["translation_version"], key
    _lexeme(db, "canjia")
    man = _build(db, survey_forms=forms)
    assert not man.is_test


# ---- 现场实测轮（2026-10-28）----

from scripts.seed_manifest import (DEFAULT_FIELD_PROTOCOL, OPEN_END,  # noqa: E402
                                   load_approvals, load_field_protocol)

PENDING = {"consent": {"consent-1.1": None, "consent-2.0": None},
           "eligibility": {"eligibility-3.0": None},
           "field_protocol": {"field-1.0": None}}
APPROVED = {k: {v: "2026-11-01 研究者确认" for v in d} for k, d in PENDING.items()}
PROTOCOL = ("field-1.0", {"lexicon_version": "lex-1.0",
                          "test_lexeme_version_ids": ["v-canjia"],
                          "training_lexeme_version_ids": ["v-xianzai"],
                          "training_valid_attempts_per_word": 3}, "draft")


def _field(db, **kw):
    if db.get(m.ResearchLexeme, "v-canjia") is None:
        _lexeme(db, "canjia")
    args = dict(consent_version="consent-1.1", eligibility_version="eligibility-3.0",
                field_protocol=PROTOCOL, approvals=APPROVED)
    args.update(kw)
    return _build(db, **args)


def test_unapproved_field_materials_only_freeze_as_test(db):
    """同意文本、纳入规则、实测协议没经研究者审定：正式配置冻结不出来，测试配置可以。"""
    with pytest.raises(ManifestError) as e:
        _field(db, approvals=PENDING)
    msg = str(e.value)
    for item in ("consent-1.1", "eligibility-3.0", "field-1.0"):
        assert item in msg
    assert _field(db, approvals=PENDING, is_test=True).is_test


def test_approved_field_manifest_carries_protocol_and_open_nationality(db):
    man = _field(db)
    assert not man.is_test
    assert man.field_protocol_version == "field-1.0"
    assert man.field_protocol["training_valid_attempts_per_word"] == 3
    assert man.eligibility_spec["nationality_any"] == [], "不限国籍"
    assert man.audio_upload is False


def test_audio_upload_only_with_the_audio_consent_text(db):
    """同意书写了上传录音才能收；用了那份同意书就必须收——两边说法一致。"""
    with pytest.raises(ManifestError):
        _field(db, audio_upload=True)                      # consent-1.1 不含录音
    with pytest.raises(ManifestError):
        _field(db, consent_version="consent-2.0")          # 同意书说上传，配置却不收
    assert _field(db, consent_version="consent-2.0", audio_upload=True).audio_upload


def test_open_ended_window_is_allowed(db):
    man = _field(db, collection_end=OPEN_END)
    assert man.collection_end_at == OPEN_END


def test_unknown_eligibility_version_is_rejected(db):
    with pytest.raises(ManifestError):
        _field(db, eligibility_version="eligibility-9.9")


def test_field_protocol_lexicon_must_match(db):
    other = (PROTOCOL[0], {**PROTOCOL[1], "lexicon_version": "lex-0.9"}, "draft")
    with pytest.raises(ManifestError):
        _field(db, field_protocol=other)


def test_shipped_field_protocol_is_consistent():
    """仓库里随 App 发布的协议：测试词与训练词不重叠、都在研究词库里。"""
    version, protocol, _ = load_field_protocol(DEFAULT_FIELD_PROTOCOL)
    assert version == "field-1.0"
    test, train = protocol["test_lexeme_version_ids"], protocol["training_lexeme_version_ids"]
    assert test and train and not set(test) & set(train)


def test_shipped_field_materials_await_the_researcher():
    """审定只能由研究者本人确认后填写。这条测试守住「开发方没有代填」：
    研究者审定之后，连同这条断言一起改。"""
    approvals = load_approvals()
    for kind, version in (("consent", "consent-1.1"), ("consent", "consent-2.0"),
                          ("eligibility", "eligibility-3.0"), ("field_protocol", "field-1.0")):
        assert approvals[kind][version] is None, f"{version} 的审定须由研究者确认后再填"
