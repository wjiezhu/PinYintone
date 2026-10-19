"""学生登录凭证的服务端校验：登录身份 = (登录方式, 该方式下的用户号)。

此前 `student/register` 直接相信客户端传来的 appleUserID——知道某人的 Apple 用户号，
就能在自己的设备上冒充他，进而拿到他的研究编号与问卷状态。
现在用户号一律取自**验过签**的凭证：

- Apple：identityToken（JWT），用 Apple 的 JWKS 验签，iss = appleid.apple.com，
  aud ∈ APPLE_BUNDLE_IDS；
- Google：ID token，用 Google 的 JWKS 验签，iss = accounts.google.com，
  aud ∈ GOOGLE_CLIENT_IDS。

两边都校验 exp（留 60 秒时钟偏差）。公钥缓存 JWKS_CACHE_SECONDS；
遇到不认识的 kid（对方轮换了密钥）提前刷新，但两次刷新至少隔一分钟，
免得一串伪造的 kid 把我们变成打对方公钥接口的放大器。

过渡期：线上已装的旧版 iOS 不上传 identityToken。ALLOW_LEGACY_UNVERIFIED_APPLE 开着时，
没带 token 的 Apple 登录照旧放行，记 warning 日志并在 users.legacy_login_at 留痕。
"""
import json
import logging
import threading
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable

import jwt
from fastapi import HTTPException

from .config import settings

log = logging.getLogger("pinyintone.identity")

PROVIDERS = ("apple", "google")
_LEEWAY_SECONDS = 60
_MIN_REFRESH_SECONDS = 60


class IdentityError(Exception):
    """凭证没通过。`code` 原样作为接口错误码的前缀返回给客户端。"""

    def __init__(self, code: str, message: str, status: int = 401):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status

    def as_http(self) -> HTTPException:
        return HTTPException(self.status, f"{self.code}：{self.message}")


def _fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=5) as resp:   # noqa: S310（固定的 https 地址）
        return json.load(resp)


class JWKSCache:
    """一个提供方的公钥集合。线程安全；`fetch` 可在测试里换成本地假实现。"""

    def __init__(self, url: str, fetch: Callable[[str], dict] = _fetch_json):
        self.url = url
        self.fetch = fetch
        self._keys: dict = {}
        self._fetched_at: float | None = None
        self._lock = threading.Lock()

    def key_for(self, kid: str | None):
        with self._lock:
            now = time.monotonic()
            stale = (self._fetched_at is None
                     or now - self._fetched_at >= settings.jwks_cache_seconds)
            unknown = kid not in self._keys and (
                self._fetched_at is None or now - self._fetched_at >= _MIN_REFRESH_SECONDS)
            if stale or unknown:
                self._refresh(now)
            key = self._keys.get(kid)
        if key is None:
            raise IdentityError("identity_token_invalid", "签名密钥不认识")
        return key

    def _refresh(self, now: float) -> None:
        try:
            data = self.fetch(self.url)
            keys = {}
            for jwk in data.get("keys", []):
                if jwk.get("kty") != "RSA" or "kid" not in jwk:
                    continue
                keys[jwk["kid"]] = jwt.PyJWK(jwk, algorithm="RS256").key
        except Exception as exc:   # 网络、JSON、密钥格式，任何一种都一样处理
            if self._keys:
                # 拿不到新的就继续用旧的；下一分钟再试
                log.warning("刷新公钥失败，继续用缓存：%s %s", self.url, exc)
                self._fetched_at = now - settings.jwks_cache_seconds + _MIN_REFRESH_SECONDS
                return
            log.error("取公钥失败：%s %s", self.url, exc)
            raise IdentityError("identity_provider_unavailable",
                                "暂时无法取得登录服务的公钥", status=503) from exc
        self._keys = keys
        self._fetched_at = now


@dataclass
class _Provider:
    issuers: tuple[str, ...]
    jwks: JWKSCache
    audiences: Callable[[], list[str]]


_PROVIDERS: dict[str, _Provider] = {
    "apple": _Provider(issuers=("https://appleid.apple.com",),
                       jwks=JWKSCache("https://appleid.apple.com/auth/keys"),
                       audiences=lambda: settings.apple_audiences),
    "google": _Provider(issuers=("https://accounts.google.com", "accounts.google.com"),
                        jwks=JWKSCache("https://www.googleapis.com/oauth2/v3/certs"),
                        audiences=lambda: settings.google_audiences),
}


def verify_token(provider: str, token: str) -> str:
    """验签并返回凭证里的用户号（sub）。失败抛 `IdentityError`。"""
    p = _PROVIDERS[provider]
    audiences = p.audiences()
    if not audiences:
        raise IdentityError("identity_not_configured",
                            f"服务端未配置 {provider} 登录的 client id / bundle id", status=503)
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise IdentityError("identity_token_invalid", "凭证格式不对") from exc
    if header.get("alg") != "RS256":
        raise IdentityError("identity_token_invalid", "凭证签名算法不对")
    key = p.jwks.key_for(header.get("kid"))
    try:
        claims = jwt.decode(
            token, key, algorithms=["RS256"], audience=audiences, issuer=list(p.issuers),
            leeway=_LEEWAY_SECONDS,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]})
    except jwt.ExpiredSignatureError as exc:
        raise IdentityError("identity_token_expired", "凭证已过期，请重新登录") from exc
    except jwt.InvalidAudienceError as exc:
        raise IdentityError("identity_token_audience", "凭证不是签给本 App 的") from exc
    except jwt.InvalidIssuerError as exc:
        raise IdentityError("identity_token_invalid", "凭证签发方不对") from exc
    except jwt.PyJWTError as exc:
        raise IdentityError("identity_token_invalid", "凭证验签失败") from exc
    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        raise IdentityError("identity_token_invalid", "凭证里没有用户号")
    return sub


@dataclass
class LoginIdentity:
    provider: str
    subject: str
    # verified：本次请求带了验过签的凭证；kept：沿用这台设备已验证过的同一身份；
    # legacy：靠过渡开关放行的未验证 Apple 登录
    how: str


def authenticate(provider: str | None, token: str | None, claimed_apple_id: str | None,
                 user) -> LoginIdentity | None:
    """决定这次注册请求的登录身份。返回 None = 没有登录身份（旧式设备档案）。

    `user` 是这台设备现有的行（可能为 None）。失败抛 HTTPException。
    """
    if provider is None:
        if not (token or claimed_apple_id):
            return None
        provider = "apple"     # 旧版 iOS 只传 appleUserID
    if provider not in PROVIDERS:
        raise HTTPException(400, f"unsupported_provider：登录方式须为 {list(PROVIDERS)} 之一")

    if token:
        try:
            sub = verify_token(provider, token)
        except IdentityError as exc:
            # 是我们自己这边的问题（没配置、取不到公钥）而不是凭证的问题时，
            # 过渡期内不让新版 iOS 因此登录不了——退回到旧版的放行方式，并大声记下来
            if (exc.code in ("identity_not_configured", "identity_provider_unavailable")
                    and provider == "apple" and claimed_apple_id
                    and settings.allow_legacy_unverified_apple):
                log.error("Apple 凭证无法校验（%s），按过渡开关放行", exc.code)
                return LoginIdentity("apple", claimed_apple_id, "legacy")
            raise exc.as_http() from exc
        if provider == "apple" and claimed_apple_id and claimed_apple_id != sub:
            raise HTTPException(401, "identity_subject_mismatch：appleUserID 与凭证里的用户号不一致")
        return LoginIdentity(provider, sub, "verified")

    # 没带凭证：这台设备已经用验过签的同一身份登录过（客户端离线后补送、改名字），
    # 沿用即可——不建立任何新的对应关系
    if (user is not None and user.auth_provider == provider and user.auth_subject
            and user.auth_verified_at is not None
            and claimed_apple_id in (None, user.auth_subject)):
        return LoginIdentity(provider, user.auth_subject, "kept")

    if provider == "apple" and claimed_apple_id and settings.allow_legacy_unverified_apple:
        log.warning("未验证的 Apple 登录按过渡开关放行（ALLOW_LEGACY_UNVERIFIED_APPLE）")
        return LoginIdentity("apple", claimed_apple_id, "legacy")
    raise HTTPException(401, "identity_token_required：须上传登录凭证（identityToken）")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)
