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


def test_shipped_materials_are_still_drafts(db):
    """现状护栏：仓库里的问卷与同意文本仍是草稿，正式配置现在冻结不出来。

    研究者审定材料、把版本号去掉 draft 之后，这条测试需要随之更新——
    它存在的目的是防止有人不经审定就把正式采集打开。
    """
    from scripts.seed_manifest import DEFAULT_SURVEY_DIR
    _lexeme(db, "canjia")
    with pytest.raises(ManifestError):
        _build(db, survey_forms=load_survey_forms(DEFAULT_SURVEY_DIR))
