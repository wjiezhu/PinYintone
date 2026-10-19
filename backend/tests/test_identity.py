"""登录身份 (provider, subject)：迁移、凭证验签、过渡开关、跨设备与删除。

Apple / Google 的公钥换成本地自签的测试密钥（不连网）：
把各提供方 JWKSCache 的 fetch 换成返回测试 JWKS 的函数。
"""
import logging
import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import identity, models, research_models
from app.config import settings
from app.database import Base, enforce_sqlite_foreign_keys, get_db
from app.main import app
from app.migrations import migrate_account_identities

BUNDLE = "Joy.PinYintone"
WEB_CLIENT = "123-web.apps.googleusercontent.com"
ANDROID_CLIENT = "123-android.apps.googleusercontent.com"
APPLE_ISS = "https://appleid.apple.com"
GOOGLE_ISS = "https://accounts.google.com"
NOW = datetime.now(timezone.utc)

KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
OTHER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _jwks(*pairs):
    keys = []
    for kid, key in pairs:
        jwk = jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key(), as_dict=True)
        jwk.update(kid=kid, alg="RS256", use="sig")
        keys.append(jwk)
    return {"keys": keys}


def _token(sub="apple-sub-1", aud=BUNDLE, iss=APPLE_ISS, key=KEY, kid="k1",
           exp_in=600, **extra):
    now = int(time.time())
    claims = {"iss": iss, "aud": aud, "sub": sub, "iat": now, "exp": now + exp_in}
    claims.update(extra)
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": kid})


def _google(sub="google-sub-1", aud=WEB_CLIENT, iss=GOOGLE_ISS, **kw):
    return _token(sub=sub, aud=aud, iss=iss, **kw)


class _Fetcher:
    def __init__(self, data):
        self.data = data
        self.calls = 0

    def __call__(self, url):
        self.calls += 1
        if isinstance(self.data, Exception):
            raise self.data
        return self.data


# ---------------- 测试库与客户端 ----------------

engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
enforce_sqlite_foreign_keys(engine)
Session = sessionmaker(bind=engine)


def _override():
    db = Session()
    try:
        yield db
    finally:
        db.close()


client = TestClient(app)


@pytest.fixture(autouse=True)
def env(monkeypatch):
    """每个用例：干净的库、自己的 get_db、测试公钥、配置齐全、过渡开关开着。

    其它测试模块在 import 时设置了 get_db 覆盖，这里用完要还原。
    """
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _override
    monkeypatch.setattr(settings, "apple_bundle_ids", BUNDLE)
    monkeypatch.setattr(settings, "google_client_ids", f"{WEB_CLIENT}, {ANDROID_CLIENT}")
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", True)
    fetchers = {}
    for name, p in identity._PROVIDERS.items():
        fetchers[name] = _Fetcher(_jwks(("k1", KEY)))
        monkeypatch.setattr(p, "jwks", identity.JWKSCache(p.jwks.url, fetch=fetchers[name]))
    yield fetchers
    if previous is None:
        app.dependency_overrides.pop(get_db, None)
    else:
        app.dependency_overrides[get_db] = previous


def _register(device, **body):
    return client.post("/student/register", json={"deviceID": device, "role": "student", **body})


def _user(device):
    db = Session()
    try:
        return db.get(models.User, device)
    finally:
        db.close()


def _links():
    db = Session()
    try:
        return {(r.provider, r.subject): r.account_id for r in db.query(models.AccountLink)}
    finally:
        db.close()


def _code(resp):
    return resp.json()["detail"].split("：")[0]


# ---------------- 迁移 ----------------

_OLD_USERS = """CREATE TABLE users (
    device_id VARCHAR PRIMARY KEY, apple_user_id VARCHAR, account_id VARCHAR,
    nickname VARCHAR, class_code VARCHAR, role VARCHAR NOT NULL,
    experiment_group VARCHAR, counterbalance_index INTEGER, native_language VARCHAR,
    spoken_languages JSON, install_date DATETIME)"""
_OLD_LINKS = """CREATE TABLE account_links (
    apple_user_id VARCHAR PRIMARY KEY, account_id VARCHAR NOT NULL UNIQUE,
    created_at DATETIME)"""


def _old_schema_db(tmp_path):
    """只认 Apple 时期的库：users 没有 auth_* 列，account_links 以 apple_user_id 为主键。"""
    eng = create_engine(f"sqlite:///{tmp_path / 'old.db'}")
    with eng.begin() as c:
        c.execute(text(_OLD_USERS))
        c.execute(text(_OLD_LINKS))
        c.execute(text("CREATE INDEX ix_account_links_account_id ON account_links (account_id)"))
        for dev, apple, acc in (("dev-A", "apple-1", "acc-111"), ("dev-B", "apple-1", "acc-111"),
                                ("dev-C", "apple-2", "acc-222"), ("dev-D", None, "acc-333")):
            c.execute(text("INSERT INTO users (device_id, apple_user_id, account_id, role) "
                           "VALUES (:d, :a, :acc, 'student')"), dict(d=dev, a=apple, acc=acc))
        c.execute(text("INSERT INTO account_links VALUES ('apple-1', 'acc-111', '2026-10-01')"))
        c.execute(text("INSERT INTO account_links VALUES ('apple-2', 'acc-222', '2026-10-02')"))
    return eng


def _start_like_main(eng):
    Base.metadata.create_all(bind=eng)
    migrate_account_identities(eng)


def test_migration_keeps_account_ids_and_moves_links_to_apple(tmp_path):
    eng = _old_schema_db(tmp_path)
    _start_like_main(eng)
    _start_like_main(eng)          # 每次启动都会跑：必须幂等
    assert "account_links" not in inspect(eng).get_table_names()
    with eng.connect() as c:
        links = set(c.execute(text(
            "SELECT provider, subject, account_id FROM account_identities")).all())
        users = {r[0]: r[1:] for r in c.execute(text(
            "SELECT device_id, auth_provider, auth_subject, account_id, apple_user_id "
            "FROM users")).all()}
    assert links == {("apple", "apple-1", "acc-111"), ("apple", "apple-2", "acc-222")}
    assert users == {
        "dev-A": ("apple", "apple-1", "acc-111", "apple-1"),
        "dev-B": ("apple", "apple-1", "acc-111", "apple-1"),
        "dev-C": ("apple", "apple-2", "acc-222", "apple-2"),
        "dev-D": (None, None, "acc-333", None),
    }


def test_migrated_account_keeps_its_id_through_verified_and_legacy_logins(tmp_path):
    """迁移后，同一 Apple 账号无论旧版（无凭证）还是新版（验过签）登录，编号都不变。"""
    eng = _old_schema_db(tmp_path)
    _start_like_main(eng)
    local = sessionmaker(bind=eng)

    def _db():
        db = local()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _db
    assert _register("dev-A", appleUserID="apple-1").status_code == 200
    assert _register("dev-new", provider="apple", appleUserID="apple-1",
                     identityToken=_token(sub="apple-1")).status_code == 200
    with eng.connect() as c:
        accs = dict(c.execute(text("SELECT device_id, account_id FROM users")).all())
    assert accs["dev-A"] == accs["dev-B"] == accs["dev-new"] == "acc-111"
    assert accs["dev-C"] == "acc-222"


def test_migration_on_fresh_database_is_a_no_op(tmp_path):
    eng = create_engine(f"sqlite:///{tmp_path / 'new.db'}")
    _start_like_main(eng)
    _start_like_main(eng)
    names = set(inspect(eng).get_table_names())
    assert "account_identities" in names and "account_links" not in names


# ---------------- Apple 验签 ----------------

def test_apple_token_verified_binds_subject_from_token():
    r = _register("dev-1", provider="apple", appleUserID="apple-sub-1", identityToken=_token())
    assert r.status_code == 200, r.text
    u = _user("dev-1")
    assert (u.auth_provider, u.auth_subject) == ("apple", "apple-sub-1")
    assert u.auth_verified_at is not None and u.legacy_login_at is None
    assert u.apple_user_id == "apple-sub-1"
    assert ("apple", "apple-sub-1") in _links()


def test_apple_token_without_claimed_id_uses_token_subject():
    assert _register("dev-1", identityToken=_token(sub="from-token")).status_code == 200
    assert _user("dev-1").auth_subject == "from-token"


@pytest.mark.parametrize("token, code", [
    (lambda: _token(key=OTHER_KEY), "identity_token_invalid"),            # 签名不对
    (lambda: _token(exp_in=-600), "identity_token_expired"),
    (lambda: _token(aud="com.someone.else"), "identity_token_audience"),
    (lambda: _token(iss="https://evil.example"), "identity_token_invalid"),
    (lambda: _token(kid="unknown"), "identity_token_invalid"),
    (lambda: "not-a-jwt", "identity_token_invalid"),
    (lambda: jwt.encode({"sub": "apple-sub-1", "aud": BUNDLE, "iss": APPLE_ISS,
                         "iat": int(time.time()), "exp": int(time.time()) + 600},
                        "x" * 32, algorithm="HS256", headers={"kid": "k1"}),
     "identity_token_invalid"),                                             # 换算法
])
def test_apple_bad_tokens_are_rejected_even_with_legacy_switch_on(token, code):
    r = _register("dev-1", provider="apple", appleUserID="apple-sub-1", identityToken=token())
    assert r.status_code == 401
    assert _code(r) == code
    assert _user("dev-1") is None          # 什么都没建


def test_apple_claimed_id_must_match_token_subject():
    r = _register("dev-1", provider="apple", appleUserID="victim",
                  identityToken=_token(sub="attacker"))
    assert r.status_code == 401 and _code(r) == "identity_subject_mismatch"


def test_google_token_is_not_accepted_as_apple():
    r = _register("dev-1", provider="apple", identityToken=_google())
    assert r.status_code == 401


# ---------------- Google 验签 ----------------

@pytest.mark.parametrize("aud", [WEB_CLIENT, ANDROID_CLIENT])
def test_google_token_verified(aud):
    r = _register("dev-g", provider="google", identityToken=_google(aud=aud))
    assert r.status_code == 200, r.text
    u = _user("dev-g")
    assert (u.auth_provider, u.auth_subject) == ("google", "google-sub-1")
    assert u.auth_verified_at is not None
    assert u.apple_user_id is None


def test_google_accepts_issuer_without_scheme():
    r = _register("dev-g", provider="google", identityToken=_google(iss="accounts.google.com"))
    assert r.status_code == 200, r.text


@pytest.mark.parametrize("token, code", [
    (lambda: _google(key=OTHER_KEY), "identity_token_invalid"),
    (lambda: _google(exp_in=-600), "identity_token_expired"),
    (lambda: _google(aud="someone-else.apps.googleusercontent.com"), "identity_token_audience"),
    (lambda: _google(iss=APPLE_ISS), "identity_token_invalid"),
])
def test_google_bad_tokens_are_rejected(token, code):
    r = _register("dev-g", provider="google", identityToken=token())
    assert r.status_code == 401 and _code(r) == code


def test_google_without_token_is_rejected_regardless_of_switch():
    r = _register("dev-g", provider="google")
    assert r.status_code == 401 and _code(r) == "identity_token_required"


def test_unknown_provider_is_rejected():
    r = _register("dev-1", provider="facebook", identityToken=_token())
    assert r.status_code == 400 and _code(r) == "unsupported_provider"


def test_google_and_apple_with_same_subject_are_different_accounts():
    _register("dev-1", provider="apple", identityToken=_token(sub="same"))
    _register("dev-2", provider="google", identityToken=_google(sub="same"))
    links = _links()
    assert links[("apple", "same")] != links[("google", "same")]


# ---------------- 过渡开关 ----------------

def test_legacy_switch_on_lets_old_ios_through_and_leaves_a_trace(caplog):
    with caplog.at_level(logging.WARNING, logger="pinyintone.identity"):
        r = _register("dev-old", appleUserID="apple-old")
    assert r.status_code == 200
    u = _user("dev-old")
    assert (u.auth_provider, u.auth_subject) == ("apple", "apple-old")
    assert u.legacy_login_at is not None and u.auth_verified_at is None
    assert any("过渡开关" in m for m in caplog.messages)


def test_legacy_switch_off_requires_token(monkeypatch):
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    r = _register("dev-old", appleUserID="apple-old")
    assert r.status_code == 401 and _code(r) == "identity_token_required"
    assert _user("dev-old") is None
    # 带了凭证照常
    assert _register("dev-new", identityToken=_token()).status_code == 200


def test_switch_off_still_allows_resend_from_an_already_verified_device(monkeypatch):
    """客户端离线时登录、凭证过期后补送（或改名字）：同一设备、同一已验证身份，沿用。"""
    _register("dev-1", provider="apple", appleUserID="apple-sub-1", identityToken=_token())
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    r = _register("dev-1", appleUserID="apple-sub-1", nickname="Amina")
    assert r.status_code == 200
    assert _user("dev-1").nickname == "Amina"
    # Android 补送：不带凭证、不带用户号
    _register("dev-g", provider="google", identityToken=_google())
    assert _register("dev-g", provider="google", nickname="Y").status_code == 200
    # 但不能借这条路换成另一个身份
    r = _register("dev-1", appleUserID="someone-else")
    assert r.status_code == 401
    assert _user("dev-1").auth_subject == "apple-sub-1"


def test_legacy_device_row_is_not_treated_as_verified(monkeypatch):
    _register("dev-1", appleUserID="apple-old")              # 过渡期未验证
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    assert _register("dev-1", appleUserID="apple-old").status_code == 401


def test_unconfigured_apple_falls_back_only_while_switch_is_on(monkeypatch):
    monkeypatch.setattr(settings, "apple_bundle_ids", "")
    r = _register("dev-1", appleUserID="apple-sub-1", identityToken=_token())
    assert r.status_code == 200
    assert _user("dev-1").auth_verified_at is None       # 没验证就不能记成已验证
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    r = _register("dev-2", appleUserID="apple-sub-1", identityToken=_token())
    assert r.status_code == 503 and _code(r) == "identity_not_configured"


def test_google_unconfigured_is_503(monkeypatch):
    monkeypatch.setattr(settings, "google_client_ids", "")
    r = _register("dev-g", provider="google", identityToken=_google())
    assert r.status_code == 503 and _code(r) == "identity_not_configured"


def test_key_server_down_is_503_not_401(env, monkeypatch):
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    env["apple"].data = OSError("down")
    r = _register("dev-1", identityToken=_token())
    assert r.status_code == 503 and _code(r) == "identity_provider_unavailable"


# ---------------- 公钥缓存 ----------------

def test_keys_are_cached(env):
    for i in range(3):
        assert _register(f"dev-{i}", identityToken=_token(sub=f"s{i}")).status_code == 200
    assert env["apple"].calls == 1


def test_unknown_kid_refreshes_but_not_more_than_once_a_minute(env, monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(identity.time, "monotonic", lambda: clock[0])
    assert _register("dev-1", identityToken=_token()).status_code == 200
    # Apple 轮换了密钥：新 kid 的凭证，公钥接口也已换新
    env["apple"].data = _jwks(("k1", KEY), ("k2", OTHER_KEY))
    rotated = _token(key=OTHER_KEY, kid="k2", sub="s2")
    clock[0] += 10
    assert _register("dev-2", identityToken=rotated).status_code == 401   # 一分钟内不重取
    assert env["apple"].calls == 1
    clock[0] += 60
    assert _register("dev-2", identityToken=rotated).status_code == 200
    assert env["apple"].calls == 2


def test_failed_refresh_keeps_using_cached_keys(env, monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(identity.time, "monotonic", lambda: clock[0])
    assert _register("dev-1", identityToken=_token()).status_code == 200
    env["apple"].data = OSError("down")
    clock[0] += settings.jwks_cache_seconds + 1
    assert _register("dev-2", identityToken=_token(sub="s2")).status_code == 200


# ---------------- 跨设备 / 换账号 ----------------

def _manifest():
    db = Session()
    db.add(research_models.ResearchManifest(
        manifest_id="m1", study_id="s1", app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f1", advice_policy_version="a1", survey_version="sv1",
        consent_version="c1", eligibility_version="e1", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=NOW - timedelta(days=1),
        collection_end_at=NOW + timedelta(days=13), frozen_at=NOW))
    db.commit()
    db.close()


def _enroll(device):
    r = client.post("/research/enroll", json={
        "internalUserID": device, "manifestID": "m1", "consentVersion": "c1",
        "consentLanguage": "zh", "consentOccurredAt": NOW.isoformat(),
        "eligibilityStatus": "eligible", "eligibilityVersion": "e1", "isTest": True})
    assert r.status_code == 200, r.text
    return r.json()["participantID"]


def test_same_google_account_on_two_devices_is_one_participant():
    _manifest()
    _register("dev-A", provider="google", identityToken=_google(sub="g1"))
    _register("dev-B", provider="google", identityToken=_google(sub="g1", aud=ANDROID_CLIENT))
    assert _enroll("dev-A") == _enroll("dev-B")
    assert _user("dev-A").account_id == _user("dev-B").account_id


def test_same_apple_account_on_two_devices_is_one_participant_verified():
    _manifest()
    _register("dev-A", identityToken=_token(sub="a1"))
    _register("dev-B", appleUserID="a1", identityToken=_token(sub="a1"))
    assert _enroll("dev-A") == _enroll("dev-B")


def test_switching_account_on_one_device_is_another_participant():
    """同一台设备：Google g1 → Apple a1 → Google g2 → 再回 g1。"""
    _manifest()
    _register("dev-A", provider="google", identityToken=_google(sub="g1"))
    p_g1 = _enroll("dev-A")
    acc_g1 = _user("dev-A").account_id
    _register("dev-A", provider="apple", identityToken=_token(sub="a1"))
    p_a1 = _enroll("dev-A")
    _register("dev-A", provider="google", identityToken=_google(sub="g2"))
    p_g2 = _enroll("dev-A")
    assert len({p_g1, p_a1, p_g2}) == 3
    _register("dev-A", provider="google", identityToken=_google(sub="g1"))
    assert _enroll("dev-A") == p_g1
    assert _user("dev-A").account_id == acc_g1


def test_switching_account_clears_verified_state_of_previous_owner(monkeypatch):
    _register("dev-A", identityToken=_token(sub="a1"))
    _register("dev-A", appleUserID="a2")                     # 旧版 iOS 换人登录
    u = _user("dev-A")
    assert u.auth_subject == "a2" and u.auth_verified_at is None


# ---------------- 删除账号 ----------------

def test_delete_removes_all_devices_of_the_identity_and_its_link():
    _register("dev-A", provider="google", identityToken=_google(sub="g1"))
    _register("dev-B", provider="google", identityToken=_google(sub="g1"))
    _register("dev-C", provider="google", identityToken=_google(sub="g2"))
    r = client.delete("/student/account", params={"deviceID": "dev-A"})
    assert r.status_code == 200
    assert sorted(r.json()["deviceIDs"]) == ["dev-A", "dev-B"]
    assert _user("dev-B") is None and _user("dev-C") is not None
    assert set(_links()) == {("google", "g2")}


def test_delete_ignores_a_claimed_apple_id_that_is_not_this_devices():
    """知道别人的 Apple 用户号，不能借删除接口删掉别人的数据。"""
    _register("victim-dev", identityToken=_token(sub="victim"))
    _register("attacker-dev", identityToken=_token(sub="attacker"))
    r = client.delete("/student/account",
                      params={"deviceID": "attacker-dev", "appleUserID": "victim"})
    assert r.status_code == 200
    assert r.json()["deviceIDs"] == ["attacker-dev"]
    assert _user("victim-dev") is not None
    assert set(_links()) == {("apple", "victim")}


def test_delete_with_legacy_apple_id_when_device_row_is_gone(monkeypatch):
    """旧版 iOS：本机这一行没建成（或已删），按 appleUserID 删其它设备——仅过渡期。"""
    _register("dev-B", appleUserID="a1")
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", False)
    r = client.delete("/student/account", params={"deviceID": "gone", "appleUserID": "a1"})
    assert r.json()["deviceIDs"] == ["gone"] and _user("dev-B") is not None
    monkeypatch.setattr(settings, "allow_legacy_unverified_apple", True)
    r = client.delete("/student/account", params={"deviceID": "gone", "appleUserID": "a1"})
    assert sorted(r.json()["deviceIDs"]) == ["dev-B", "gone"] and _user("dev-B") is None
    assert _links() == {}


def test_deleted_account_signing_in_again_gets_a_new_id():
    _register("dev-A", identityToken=_token(sub="a1"))
    old = _user("dev-A").account_id
    client.delete("/student/account", params={"deviceID": "dev-A"})
    _register("dev-A", identityToken=_token(sub="a1"))
    assert _user("dev-A").account_id != old
