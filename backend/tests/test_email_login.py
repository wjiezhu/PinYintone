"""邮箱验证码登录（provider = email）：验证码、频率限制、发信器配置、账号流程、删除。

发信器换成记录收件箱的假实现，不连网；Resend 的 HTTP 调用把 urlopen 换掉。
时间用可调的假时钟（email_login._now）。
"""
import json
import logging
import urllib.error
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import email_login, email_sender, models, research_models
from app.config import settings
from app.database import Base, enforce_sqlite_foreign_keys, get_db
from app.main import app

engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False},
                       poolclass=StaticPool)
enforce_sqlite_foreign_keys(engine)
Session = sessionmaker(bind=engine)
client = TestClient(app)
START = datetime(2026, 10, 19, 8, 0, tzinfo=timezone.utc)


def _override():
    db = Session()
    try:
        yield db
    finally:
        db.close()


class _Outbox:
    def __init__(self):
        self.sent = []

    def send_code(self, to, code, ttl_minutes):
        self.sent.append((to, code, ttl_minutes))

    def last(self, to=None):
        return [c for t, c, _ in self.sent if to is None or t == to.strip().lower()][-1]


class _Clock:
    def __init__(self):
        self.now = START

    def __call__(self):
        return self.now

    def advance(self, **kw):
        self.now += timedelta(**kw)


@pytest.fixture(autouse=True)
def env(monkeypatch):
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = _override
    for name, value in (("app_env", "development"), ("email_sender", ""),
                        ("email_from", ""), ("resend_api_key", ""), ("smtp_host", ""),
                        ("email_code_per_email_per_hour", 5),
                        ("email_code_per_ip_per_hour", 30), ("trusted_proxy_hops", 1)):
        monkeypatch.setattr(settings, name, value)
    outbox = _Outbox()
    monkeypatch.setattr(email_sender, "get_sender", lambda: outbox)
    clock = _Clock()
    monkeypatch.setattr(email_login, "_now", clock)
    yield outbox, clock
    if previous is None:
        app.dependency_overrides.pop(get_db, None)
    else:
        app.dependency_overrides[get_db] = previous


@pytest.fixture
def outbox(env):
    return env[0]


@pytest.fixture
def clock(env):
    return env[1]


def _request(email, ip="203.0.113.1"):
    return client.post("/student/email/request-code", json={"email": email},
                       headers={"X-Forwarded-For": ip})


def _login(email, code, device="dev-A", **body):
    return client.post("/student/email/login", json={
        "email": email, "code": code, "deviceID": device, "role": "student", **body})


def _code(resp):
    return resp.json()["detail"].split("：")[0]


def _wrong(code):
    return f"{(int(code) + 1) % 10 ** 6:06d}"


def _user(device):
    db = Session()
    try:
        return db.get(models.User, device)
    finally:
        db.close()


def _rows(model):
    db = Session()
    try:
        return db.query(model).all()
    finally:
        db.close()


def _sign_in(outbox, clock, email, device="dev-A"):
    clock.advance(seconds=61)
    assert _request(email).status_code == 200
    r = _login(email, outbox.last(email), device)
    assert r.status_code == 200, r.text
    return _user(device)


# ---------------- 验证码 ----------------

def test_correct_code_logs_in_with_hashed_email_subject(outbox):
    r = _request("  Alice@Example.COM ")
    assert r.status_code == 200
    assert outbox.sent[0][0] == "alice@example.com" and outbox.sent[0][2] == 10
    code = outbox.last()
    assert len(code) == 6 and code.isdigit()
    r = _login("alice@example.com", code, nickname="Alice", nativeLanguage="fr",
               spokenLanguages=["fr", "ar"])
    assert r.status_code == 200, r.text
    u = _user("dev-A")
    assert u.auth_provider == "email"
    assert u.auth_subject == email_login.email_subject("alice@example.com")
    assert "alice" not in u.auth_subject
    assert u.auth_verified_at is not None and u.account_id
    assert u.nickname == "Alice" and u.spoken_languages == ["fr", "ar"] and u.class_code is None


def test_code_and_email_are_not_stored_in_clear(outbox):
    _request("bob@example.com")
    code = outbox.last()
    (row,) = _rows(models.EmailLoginCode)
    assert code not in row.code_hash and "bob" not in row.email_hash
    (req,) = _rows(models.EmailCodeRequest)
    assert "203.0.113.1" not in req.ip_hash


def test_gmail_dots_and_plus_are_not_folded(outbox, clock):
    a = _sign_in(outbox, clock, "first.last@gmail.com", "dev-A")
    b = _sign_in(outbox, clock, "firstlast+x@gmail.com", "dev-B")
    assert a.account_id != b.account_id


def test_wrong_code_counts_down_then_exhausts(outbox):
    _request("c@example.com")
    code = outbox.last()
    for left in (4, 3, 2, 1):
        r = _login("c@example.com", _wrong(code))
        assert r.status_code == 401 and _code(r) == "email_code_invalid"
        assert f"{left} 次" in r.json()["detail"]
    r = _login("c@example.com", _wrong(code))
    assert _code(r) == "email_code_attempts_exceeded"
    # 第 6 次就算对了也不行：验证码已作废
    r = _login("c@example.com", code)
    assert r.status_code == 401 and _user("dev-A") is None


def test_code_is_single_use(outbox):
    _request("d@example.com")
    code = outbox.last()
    assert _login("d@example.com", code).status_code == 200
    r = _login("d@example.com", code, device="dev-B")
    assert r.status_code == 401 and _code(r) == "email_code_invalid"


def test_expired_code(outbox, clock):
    _request("e@example.com")
    code = outbox.last()
    clock.advance(minutes=10, seconds=1)
    r = _login("e@example.com", code)
    assert r.status_code == 401 and _code(r) == "email_code_expired"
    r = _login("e@example.com", code)
    assert _code(r) == "email_code_invalid"


def test_code_still_valid_just_before_expiry(outbox, clock):
    _request("e@example.com")
    clock.advance(minutes=9, seconds=59)
    assert _login("e@example.com", outbox.last()).status_code == 200


def test_new_code_replaces_old_one(outbox, clock):
    _request("f@example.com")
    old = outbox.last()
    clock.advance(seconds=61)
    _request("f@example.com")
    new = outbox.last()
    if old != new:
        assert _code(_login("f@example.com", old)) == "email_code_invalid"
    assert _login("f@example.com", new).status_code == 200


def test_code_for_another_email_does_not_work(outbox):
    _request("g@example.com")
    _request("h@example.com")
    r = _login("h@example.com", outbox.last("g@example.com"))
    if outbox.last("g@example.com") != outbox.last("h@example.com"):
        assert r.status_code == 401


def test_login_without_any_code_requested():
    r = _login("nobody@example.com", "123456")
    assert r.status_code == 401 and _code(r) == "email_code_invalid"


@pytest.mark.parametrize("code", ["12345", "1234567", "abcdef", ""])
def test_malformed_code_does_not_use_an_attempt(outbox, code):
    _request("i@example.com")
    r = _login("i@example.com", code)
    assert r.status_code == 400 and _code(r) == "email_code_format"
    (row,) = _rows(models.EmailLoginCode)
    assert row.attempts == 0


@pytest.mark.parametrize("email", ["", "no-at-sign", "a@b", "a b@example.com", "a@@example.com"])
def test_invalid_email_is_rejected(outbox, email):
    r = _request(email)
    assert r.status_code == 400 and _code(r) == "email_invalid"
    assert outbox.sent == []


# ---------------- 冷却与频率限制 ----------------

def test_resend_cooldown_60_seconds(outbox, clock):
    assert _request("j@example.com").status_code == 200
    clock.advance(seconds=30)
    r = _request("J@example.com")
    assert r.status_code == 429 and _code(r) == "email_code_cooldown"
    assert r.headers["Retry-After"] == "30"
    clock.advance(seconds=30)
    assert _request("j@example.com").status_code == 200
    assert len(outbox.sent) == 2


def test_cooldown_is_per_email(outbox):
    assert _request("k1@example.com").status_code == 200
    assert _request("k2@example.com").status_code == 200


def test_hourly_limit_per_email(outbox, clock):
    for _ in range(5):
        assert _request("l@example.com", ip=f"198.51.100.{_}").status_code == 200
        clock.advance(seconds=61)
    r = _request("l@example.com", ip="198.51.100.99")
    assert r.status_code == 429 and _code(r) == "email_code_rate_limited"
    clock.advance(hours=1)
    assert _request("l@example.com").status_code == 200


def test_hourly_limit_per_ip(outbox, clock, monkeypatch):
    monkeypatch.setattr(settings, "email_code_per_ip_per_hour", 3)
    for i in range(3):
        assert _request(f"m{i}@example.com", ip="192.0.2.7").status_code == 200
    r = _request("m9@example.com", ip="192.0.2.7")
    assert r.status_code == 429 and _code(r) == "email_code_rate_limited"
    assert _request("m9@example.com", ip="192.0.2.8").status_code == 200
    clock.advance(hours=1, seconds=1)
    assert _request("m10@example.com", ip="192.0.2.7").status_code == 200


def test_ip_is_taken_from_the_trusted_proxy_hop(outbox, monkeypatch):
    """客户端自己写在 X-Forwarded-For 左边的地址不能用来绕过 IP 上限。"""
    monkeypatch.setattr(settings, "email_code_per_ip_per_hour", 1)
    assert _request("n1@example.com", ip="1.1.1.1, 192.0.2.7").status_code == 200
    r = _request("n2@example.com", ip="2.2.2.2, 192.0.2.7")
    assert r.status_code == 429


def test_rejected_requests_send_no_mail(outbox, clock):
    _request("o@example.com")
    _request("o@example.com")
    assert len(outbox.sent) == 1


# ---------------- 不暴露邮箱是否存在 ----------------

def test_request_response_is_identical_for_registered_and_unknown_emails(outbox, clock):
    _sign_in(outbox, clock, "known@example.com")
    clock.advance(seconds=61)
    known = _request("known@example.com")
    unknown = _request("unknown@example.com")
    assert known.status_code == unknown.status_code == 200
    assert known.json() == unknown.json() == {
        "sent": True, "expiresInSeconds": 600, "resendAfterSeconds": 60}
    assert {t for t, _, _ in outbox.sent[-2:]} == {"known@example.com", "unknown@example.com"}


# ---------------- 账号流程 ----------------

def _manifest():
    now = datetime.now(timezone.utc)
    db = Session()
    db.add(research_models.ResearchManifest(
        manifest_id="m1", study_id="s1", app_version="2.0", build_number="1",
        lexicon_version="lex1", scoring_version="sc1", scoring_spec={},
        feedback_version="f1", advice_policy_version="a1", survey_version="sv1",
        consent_version="c1", eligibility_version="e1", eligibility_spec={},
        post_trigger_count=5, post_trigger_scope="fixed_word_result_displayed",
        collection_start_at=now - timedelta(days=1),
        collection_end_at=now + timedelta(days=13), frozen_at=now))
    db.commit()
    db.close()


def _enroll(device):
    r = client.post("/research/enroll", json={
        "internalUserID": device, "manifestID": "m1", "consentVersion": "c1",
        "consentLanguage": "zh", "consentOccurredAt": datetime.now(timezone.utc).isoformat(),
        "eligibilityStatus": "eligible", "eligibilityVersion": "e1", "isTest": True})
    assert r.status_code == 200, r.text
    return r.json()["participantID"]


def test_same_email_on_two_devices_is_one_account(outbox, clock):
    _manifest()
    a = _sign_in(outbox, clock, "p@example.com", "dev-A")
    b = _sign_in(outbox, clock, "P@Example.com", "dev-B")
    assert a.account_id == b.account_id
    assert _enroll("dev-A") == _enroll("dev-B")


def test_switching_email_on_one_device_is_another_account(outbox, clock):
    _manifest()
    first = _sign_in(outbox, clock, "q1@example.com").account_id
    p1 = _enroll("dev-A")
    second = _sign_in(outbox, clock, "q2@example.com").account_id
    assert first != second and _enroll("dev-A") != p1
    # 原来那位再登录回来，还是原来的编号与参与者
    assert _sign_in(outbox, clock, "q1@example.com").account_id == first
    assert _enroll("dev-A") == p1


def test_email_and_google_are_different_accounts_and_not_merged(outbox, clock, monkeypatch):
    """同一台设备从 Google 换到邮箱：换人，不沿用上一位的编号——即便用户号碰巧相同。"""
    db = Session()
    db.add(models.User(device_id="dev-A", role="student", auth_provider="google",
                       auth_subject=email_login.email_subject("r@example.com"),
                       account_id="acc-google", auth_verified_at=START))
    db.add(models.AccountLink(provider="google",
                              subject=email_login.email_subject("r@example.com"),
                              account_id="acc-google"))
    db.commit()
    db.close()
    u = _sign_in(outbox, clock, "r@example.com")
    assert u.auth_provider == "email" and u.account_id != "acc-google"


def test_register_without_token_keeps_the_email_identity(outbox, clock):
    """登录过的设备补送资料 / 改名字：/student/register 带 provider=email、不带凭证。"""
    acc = _sign_in(outbox, clock, "s@example.com").account_id
    r = client.post("/student/register", json={
        "deviceID": "dev-A", "role": "student", "provider": "email", "nickname": "new"})
    assert r.status_code == 200, r.text
    u = _user("dev-A")
    assert u.nickname == "new" and u.account_id == acc and u.auth_provider == "email"


def test_register_cannot_claim_an_email_identity_on_a_new_device():
    r = client.post("/student/register", json={
        "deviceID": "dev-X", "role": "student", "provider": "email",
        "identityToken": "whatever"})
    assert r.status_code == 401 and _code(r) == "email_login_required"
    r = client.post("/student/register", json={
        "deviceID": "dev-X", "role": "student", "provider": "email"})
    assert r.status_code == 401 and _code(r) == "email_login_required"


# ---------------- 删除账号 ----------------

def test_delete_account_clears_email_identity_codes_and_request_log(outbox, clock):
    _sign_in(outbox, clock, "t@example.com", "dev-A")
    _sign_in(outbox, clock, "t@example.com", "dev-B")
    clock.advance(seconds=61)
    _request("t@example.com")                       # 还有一个没用的验证码
    _sign_in(outbox, clock, "other@example.com", "dev-C")
    r = client.delete("/student/account", params={"deviceID": "dev-A"})
    assert r.status_code == 200
    assert sorted(r.json()["deviceIDs"]) == ["dev-A", "dev-B"]
    t = email_login.email_subject("t@example.com")
    assert all(row.email_hash != t for row in _rows(models.EmailLoginCode))
    assert all(row.email_hash != t for row in _rows(models.EmailCodeRequest))
    assert all(link.subject != t for link in _rows(models.AccountLink))
    other = email_login.email_subject("other@example.com")
    assert any(row.email_hash == other for row in _rows(models.EmailLoginCode))
    assert _user("dev-C") is not None


def test_deleted_email_account_signing_in_again_gets_a_new_id(outbox, clock):
    old = _sign_in(outbox, clock, "u@example.com").account_id
    client.delete("/student/account", params={"deviceID": "dev-A"})
    assert _sign_in(outbox, clock, "u@example.com").account_id != old


# ---------------- 发信器配置 ----------------

@pytest.fixture
def real_sender(monkeypatch):
    """不用假收件箱，走真的 get_sender。"""
    monkeypatch.undo()
    for name, value in (("email_sender", ""), ("email_from", ""), ("resend_api_key", ""),
                        ("smtp_host", ""), ("trusted_proxy_hops", 1),
                        ("email_code_per_email_per_hour", 5), ("email_code_per_ip_per_hour", 30)):
        monkeypatch.setattr(settings, name, value)
    app.dependency_overrides[get_db] = _override


@pytest.mark.parametrize("sender,extra", [
    ("", {}),                                               # 生产没设 EMAIL_SENDER
    ("console", {}),                                        # 生产不许只写日志
    ("resend", {}),                                         # 缺 key 和发件人
    ("resend", {"resend_api_key": "re_x"}),                 # 缺发件人
    ("smtp", {"email_from": "a@mail.example.com"}),         # 缺 SMTP_HOST
    ("mailgun", {}),                                        # 不认识的发信器
])
def test_production_misconfiguration_is_503(real_sender, monkeypatch, sender, extra):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "email_sender", sender)
    for k, v in extra.items():
        monkeypatch.setattr(settings, k, v)
    r = _request("v@example.com")
    assert r.status_code == 503 and _code(r) == "email_not_configured"
    assert _rows(models.EmailLoginCode) == [] and _rows(models.EmailCodeRequest) == []


def test_production_is_inferred_from_postgresql(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "")
    monkeypatch.setattr(settings, "database_url", "postgresql://u:p@h/db")
    assert settings.is_production
    monkeypatch.setattr(settings, "app_env", "development")
    assert not settings.is_production
    monkeypatch.setattr(settings, "app_env", "")
    monkeypatch.setattr(settings, "database_url", "sqlite:///./x.db")
    assert not settings.is_production


def test_development_defaults_to_console_and_logs_the_code(real_sender, monkeypatch, caplog):
    monkeypatch.setattr(settings, "app_env", "development")
    with caplog.at_level(logging.WARNING, logger="pinyintone.email"):
        assert _request("w@example.com").status_code == 200
    assert "w@example.com" in caplog.text
    (line,) = [r for r in caplog.records if "console" in r.getMessage()]
    code = line.args[1]
    assert _login("w@example.com", code).status_code == 200


class _FakeResponse:
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return b'{"id":"x"}'


def test_resend_sender_posts_to_the_http_api(real_sender, monkeypatch):
    monkeypatch.setattr(settings, "app_env", "production")
    monkeypatch.setattr(settings, "email_sender", "resend")
    monkeypatch.setattr(settings, "resend_api_key", "re_test")
    monkeypatch.setattr(settings, "email_from", "Pinyintone <login@mail.example.com>")
    calls = []

    def fake_urlopen(req, timeout):
        calls.append(req)
        return _FakeResponse()

    monkeypatch.setattr(email_sender.urllib.request, "urlopen", fake_urlopen)
    assert _request("x@example.com").status_code == 200
    (req,) = calls
    assert req.full_url == "https://api.resend.com/emails"
    assert req.get_header("Authorization") == "Bearer re_test"
    payload = json.loads(req.data)
    assert payload["to"] == ["x@example.com"]
    assert payload["from"] == "Pinyintone <login@mail.example.com>"
    body = payload["text"]
    assert "验证码" in body and "verification code" in body and "code de vérification" in body
    assert "10" in body and "http" not in body.lower() and "www." not in body


def test_resend_failure_is_503_and_leaves_no_code_or_cooldown(real_sender, monkeypatch):
    monkeypatch.setattr(settings, "email_sender", "resend")
    monkeypatch.setattr(settings, "resend_api_key", "re_test")
    monkeypatch.setattr(settings, "email_from", "login@mail.example.com")

    def failing(req, timeout):
        raise urllib.error.URLError("down")

    monkeypatch.setattr(email_sender.urllib.request, "urlopen", failing)
    r = _request("y@example.com")
    assert r.status_code == 503 and _code(r) == "email_send_failed"
    assert _rows(models.EmailLoginCode) == [] and _rows(models.EmailCodeRequest) == []


def test_mail_body_has_code_and_ttl_in_three_languages_without_links():
    subject, body = email_sender.compose("042917", 10)
    assert "042917" in subject
    assert body.count("042917") == 3 and body.count("10") == 3
    assert "http" not in body.lower()
