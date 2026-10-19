"""邮箱验证码登录：provider = email。

给用不了 Google 的手机（中国大陆的参与者）一个所有手机都能用的登录方式。

用户号（auth_subject）是规范化邮箱的 SHA-256，**不存邮箱明文**——`users` 表约定不含 PII，
研究侧本来也只认 account_id。规范化只做去首尾空格、转小写，不做 Gmail 去点 / 去 +tag：
那是服务商各自的规则，猜错了就会把两个人并成一个参与者。

同一个人用 Google 和邮箱各登录一次是两个账号；**不按邮箱自动合并**（Google 账号的邮箱
不一定是这个人此刻能收信的邮箱，合并会让一个人接管另一个人的研究身份）。

验证码：
- 6 位数字，10 分钟内有效；只存 HMAC(服务端密钥, 盐 + 邮箱 + 验证码)；
- 每个验证码最多试 5 次，用过即作废；新验证码发出时，同一邮箱的旧验证码作废；
- 同一邮箱 60 秒内不重发；同一邮箱、同一 IP 每小时各有上限（config.py）；
- 请求验证码时不看这个邮箱有没有注册过：返回一样，也一样真的发信，不暴露邮箱是否存在。
"""
import hashlib
import hmac
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, Request
from sqlalchemy import update
from sqlalchemy.orm import Session

from . import email_sender, models
from .config import settings

CODE_TTL = timedelta(minutes=10)
RESEND_COOLDOWN = timedelta(seconds=60)
MAX_ATTEMPTS = 5
_RATE_WINDOW = timedelta(hours=1)
_KEEP_ROWS = timedelta(days=1)
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: datetime) -> datetime:
    # SQLite 读回来是不带时区的（存的就是 UTC）
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def normalize_email(raw: str) -> str:
    email = (raw or "").strip().lower()
    if len(email) > 254 or not _EMAIL_RE.match(email):
        raise HTTPException(400, "email_invalid：邮箱格式不对")
    return email


def email_subject(email: str) -> str:
    """邮箱登录身份的用户号。`email` 须已规范化。"""
    return hashlib.sha256(email.encode()).hexdigest()


def _hmac(*parts: str) -> str:
    return hmac.new(settings.jwt_secret.encode(), ":".join(parts).encode(),
                    hashlib.sha256).hexdigest()


def client_ip(request: Request) -> str:
    hops = settings.trusted_proxy_hops
    forwarded = request.headers.get("x-forwarded-for")
    if hops > 0 and forwarded:
        chain = [p.strip() for p in forwarded.split(",") if p.strip()]
        if chain:
            # 每层可信代理在右边追加一个地址；再往左的是客户端自己写的，可以伪造
            return chain[-min(hops, len(chain))]
    return request.client.host if request.client else "unknown"


def request_code(db: Session, raw_email: str, ip: str) -> dict:
    email = normalize_email(raw_email)
    try:
        sender = email_sender.get_sender()
    except email_sender.EmailNotConfigured as exc:
        raise HTTPException(503, f"email_not_configured：邮件服务未配置（{exc}）") from exc

    now = _now()
    subject = email_subject(email)
    ip_hash = _hmac("ip", ip)
    db.query(models.EmailCodeRequest).filter(
        models.EmailCodeRequest.created_at < now - _KEEP_ROWS).delete(synchronize_session=False)
    db.query(models.EmailLoginCode).filter(
        models.EmailLoginCode.expires_at < now - _KEEP_ROWS).delete(synchronize_session=False)

    recent = (db.query(models.EmailCodeRequest)
              .filter(models.EmailCodeRequest.email_hash == subject,
                      models.EmailCodeRequest.created_at > now - _RATE_WINDOW)
              .order_by(models.EmailCodeRequest.created_at.desc()).all())
    if recent:
        wait = _aware(recent[0].created_at) + RESEND_COOLDOWN - now
        if wait > timedelta(0):
            seconds = max(1, int(wait.total_seconds() + 0.999))
            raise HTTPException(429, f"email_code_cooldown：请 {seconds} 秒后再获取",
                                headers={"Retry-After": str(seconds)})
    if len(recent) >= settings.email_code_per_email_per_hour:
        raise HTTPException(429, "email_code_rate_limited：这个邮箱获取验证码太频繁，请一小时后再试",
                            headers={"Retry-After": "3600"})
    ip_count = (db.query(models.EmailCodeRequest)
                .filter(models.EmailCodeRequest.ip_hash == ip_hash,
                        models.EmailCodeRequest.created_at > now - _RATE_WINDOW).count())
    if ip_count >= settings.email_code_per_ip_per_hour:
        raise HTTPException(429, "email_code_rate_limited：获取验证码太频繁，请一小时后再试",
                            headers={"Retry-After": "3600"})

    # 同一邮箱只留最新的一个验证码
    db.query(models.EmailLoginCode).filter(
        models.EmailLoginCode.email_hash == subject,
        models.EmailLoginCode.consumed_at.is_(None)).update(
        {"consumed_at": now}, synchronize_session=False)
    code = f"{secrets.randbelow(10 ** 6):06d}"
    salt = secrets.token_hex(16)
    db.add(models.EmailLoginCode(
        id=str(uuid.uuid4()), email_hash=subject, salt=salt,
        code_hash=_hmac(salt, subject, code), created_at=now, expires_at=now + CODE_TTL,
        attempts=0))
    db.add(models.EmailCodeRequest(email_hash=subject, ip_hash=ip_hash, created_at=now))
    db.flush()
    try:
        sender.send_code(email, code, int(CODE_TTL.total_seconds() // 60))
    except email_sender.EmailSendFailed as exc:
        # 没发出去：验证码与流水一起撤销，不占冷却与配额
        db.rollback()
        raise HTTPException(503, "email_send_failed：验证码邮件暂时发不出去，请稍后再试") from exc
    db.commit()
    return {"sent": True,
            "expiresInSeconds": int(CODE_TTL.total_seconds()),
            "resendAfterSeconds": int(RESEND_COOLDOWN.total_seconds())}


def verify_code(db: Session, raw_email: str, code: str) -> str:
    """验证码对了返回用户号（email_subject）；不对抛 401。无论对错，结果都已 commit。"""
    email = normalize_email(raw_email)
    code = (code or "").strip()
    if not re.fullmatch(r"\d{6}", code):
        raise HTTPException(400, "email_code_format：验证码是 6 位数字")
    subject = email_subject(email)
    now = _now()
    row = (db.query(models.EmailLoginCode)
           .filter(models.EmailLoginCode.email_hash == subject,
                   models.EmailLoginCode.consumed_at.is_(None))
           .order_by(models.EmailLoginCode.created_at.desc()).first())
    if row is None:
        raise HTTPException(401, "email_code_invalid：验证码不对或已失效，请重新获取")
    if _aware(row.expires_at) <= now:
        row.consumed_at = now
        db.commit()
        raise HTTPException(401, "email_code_expired：验证码已过期，请重新获取")

    # 先占一次尝试（原子地，并发请求不能多试），再比对
    took = db.execute(
        update(models.EmailLoginCode)
        .where(models.EmailLoginCode.id == row.id,
               models.EmailLoginCode.consumed_at.is_(None),
               models.EmailLoginCode.attempts < MAX_ATTEMPTS)
        .values(attempts=models.EmailLoginCode.attempts + 1)).rowcount
    if took != 1:
        db.commit()
        raise HTTPException(401, "email_code_attempts_exceeded：尝试次数太多，请重新获取验证码")
    db.refresh(row)

    if not hmac.compare_digest(row.code_hash, _hmac(row.salt, subject, code)):
        left = MAX_ATTEMPTS - row.attempts
        if left <= 0:
            row.consumed_at = now
            db.commit()
            raise HTTPException(401, "email_code_attempts_exceeded：尝试次数太多，请重新获取验证码")
        db.commit()
        raise HTTPException(401, f"email_code_invalid：验证码不对，还可以试 {left} 次")

    used = db.execute(
        update(models.EmailLoginCode)
        .where(models.EmailLoginCode.id == row.id, models.EmailLoginCode.consumed_at.is_(None))
        .values(consumed_at=now)).rowcount
    db.commit()
    if used != 1:
        raise HTTPException(401, "email_code_invalid：验证码不对或已失效，请重新获取")
    return subject


def forget(db: Session, subject: str) -> None:
    """删除账号：这个邮箱的全部验证码与发送流水。调用方负责 commit。"""
    db.query(models.EmailLoginCode).filter(
        models.EmailLoginCode.email_hash == subject).delete(synchronize_session=False)
    db.query(models.EmailCodeRequest).filter(
        models.EmailCodeRequest.email_hash == subject).delete(synchronize_session=False)
