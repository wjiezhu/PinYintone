"""GET /api/app-version/android：值来自配置，没配好时如实返回「没有发布信息」。"""
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)

FIELDS = ("android_latest_version_code", "android_latest_version_name", "android_min_version_code",
          "android_download_url", "android_release_notes_zh", "android_release_notes_en",
          "android_release_notes_fr", "android_release_notes_ar")


@pytest.fixture(autouse=True)
def restore_settings():
    saved = {f: getattr(settings, f) for f in FIELDS}
    yield
    for f, v in saved.items():
        setattr(settings, f, v)


def _configure(**kw):
    base = dict(android_latest_version_code=3, android_latest_version_name="0.3.0",
                android_min_version_code=2, android_download_url="https://example.org/pinyintone.apk",
                android_release_notes_zh="修复录音", android_release_notes_en="", android_release_notes_fr="",
                android_release_notes_ar="")
    base.update(kw)
    for k, v in base.items():
        setattr(settings, k, v)


def test_published_values_come_from_settings():
    _configure(android_release_notes_fr="  Correctifs  ")
    r = client.get("/api/app-version/android")
    assert r.status_code == 200
    assert r.headers["cache-control"] == "no-cache"
    assert r.json() == {
        "platform": "android", "published": True,
        "latestVersionCode": 3, "latestVersionName": "0.3.0", "minSupportedVersionCode": 2,
        "downloadUrl": "https://example.org/pinyintone.apk",
        # 空的语言不出现；首尾空白去掉
        "releaseNotes": {"zh": "修复录音", "fr": "Correctifs"},
    }


def test_defaults_mean_nothing_published():
    _configure(android_latest_version_code=0, android_download_url="")
    body = client.get("/api/app-version/android").json()
    assert body["published"] is False
    assert body["latestVersionCode"] is None and body["downloadUrl"] is None


@pytest.mark.parametrize("url", ["http://example.org/a.apk", "javascript:alert(1)", "example.org/a.apk",
                                 "https://", "file:///sdcard/a.apk"])
def test_non_https_download_url_is_not_published(url):
    # App 把地址交给系统浏览器；只放行 https，配错时宁可不提示
    _configure(android_download_url=url)
    assert client.get("/api/app-version/android").json()["published"] is False


def test_min_version_never_exceeds_latest():
    _configure(android_latest_version_code=3, android_min_version_code=9)
    assert client.get("/api/app-version/android").json()["minSupportedVersionCode"] == 3


def test_missing_version_name_falls_back_to_code():
    _configure(android_latest_version_name="  ")
    assert client.get("/api/app-version/android").json()["latestVersionName"] == "3"


def test_ios_is_not_distributed_here():
    assert client.get("/api/app-version/ios").status_code == 404


def test_needs_no_login():
    _configure()
    assert client.get("/api/app-version/android", headers={}).status_code == 200
