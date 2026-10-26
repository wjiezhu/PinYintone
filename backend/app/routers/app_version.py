"""App 新版本检查。

Android 安装包不上 Google Play，由研究者直接发下载地址（摩洛哥、中国两路都是）。
已装的 App 启动时请求一次这里：有新版本给可关闭的提示，低于最低支持版本提示必须更新。
App 只把 `downloadUrl` 交给系统浏览器，自己不下载、不安装安装包。

值全部来自配置 / 环境变量（见 config.py 的 ANDROID_*），发新版只改环境变量，不改代码。
不需要登录，不读也不写任何用户数据。
"""
from urllib.parse import urlparse

from fastapi import APIRouter, HTTPException, Response

from ..config import settings

router = APIRouter(prefix="/api/app-version", tags=["app-version"])


def _https_url(value: str) -> str | None:
    url = value.strip()
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        return None
    return url


@router.get("/android")
def android_version(response: Response):
    # 发了新版要尽快让人看到：不让中间层长时间缓存
    response.headers["Cache-Control"] = "no-cache"
    download_url = _https_url(settings.android_download_url)
    latest = max(settings.android_latest_version_code, 0)
    notes = {
        lang: text.strip()
        for lang, text in (
            ("zh", settings.android_release_notes_zh),
            ("en", settings.android_release_notes_en),
            ("fr", settings.android_release_notes_fr),
            ("ar", settings.android_release_notes_ar),
        )
        if text.strip()
    }
    if download_url is None or latest == 0:
        # 没配好（或地址不是 https）：如实说「没有发布信息」，App 什么也不提示
        return {
            "platform": "android",
            "published": False,
            "latestVersionCode": None,
            "latestVersionName": None,
            "minSupportedVersionCode": None,
            "downloadUrl": None,
            "releaseNotes": {},
        }
    return {
        "platform": "android",
        "published": True,
        "latestVersionCode": latest,
        "latestVersionName": settings.android_latest_version_name.strip() or str(latest),
        # 最低支持版本不会高于最新版本：配错时按最新版本算，免得所有人永远被要求更新
        "minSupportedVersionCode": min(max(settings.android_min_version_code, 0), latest),
        "downloadUrl": download_url,
        "releaseNotes": notes,
    }


@router.get("/{platform}")
def other_platform(platform: str):
    # iOS 走 App Store 更新，不在这里发布
    raise HTTPException(status_code=404, detail="no direct-distribution channel for this platform")
