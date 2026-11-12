"""发送登录验证码邮件。

发信器是一个很窄的接口（`send_code`），由 EMAIL_SENDER 选择实现：

- `console`：只写日志，不发信。开发与测试用；**生产环境拒绝使用**；
- `resend`：Resend 的 HTTP API（标准库 urllib，不装 SDK）；
- `smtp`：标准库 smtplib。阿里云邮件推送、Amazon SES 等都提供 SMTP 接口，
  换到这些服务商只改环境变量，不改代码。

再接一家只有 HTTP API 的服务商：写一个带 `send_code` 的类，登记到 `_FACTORIES`。

邮件正文只有验证码和有效期（中文、英文、法文），**不放链接**——
放了链接的验证码邮件更容易被判成钓鱼，也会诱导用户在邮件里点来点去。
"""
import json
import logging
import smtplib
import ssl
import urllib.error
import urllib.request
from email.message import EmailMessage
from email.utils import formataddr, formatdate, make_msgid, parseaddr
from typing import Protocol

from .config import settings

log = logging.getLogger("pinyintone.email")


class EmailNotConfigured(Exception):
    """发信器没配好。接口返回 503 email_not_configured。"""


class EmailSendFailed(Exception):
    """服务商拒收或连不上。接口返回 503 email_send_failed。"""


class EmailSender(Protocol):
    def send_code(self, to: str, code: str, ttl_minutes: int) -> None: ...


def compose(code: str, ttl_minutes: int) -> tuple[str, str]:
    """(标题, 纯文本正文)。"""
    subject = f"Pinyintone {code} — 验证码 / Verification code / Code de vérification"
    body = (
        f"您的 Pinyintone 验证码是：{code}\n"
        f"{ttl_minutes} 分钟内有效。如果不是您本人操作，请忽略这封邮件。\n"
        "\n"
        f"Your Pinyintone verification code is: {code}\n"
        f"It expires in {ttl_minutes} minutes. If you did not request it, ignore this email.\n"
        "\n"
        f"Votre code de vérification Pinyintone est : {code}\n"
        f"Il est valable {ttl_minutes} minutes. Si vous n'avez rien demandé, "
        "ignorez cet e-mail.\n"
    )
    return subject, body


DISPLAY_NAME = "Pinyintone"


def with_display_name(sender: str) -> str:
    """EMAIL_FROM 只写了地址时补上发件人名称。

    收件端看到的是「Pinyintone」而不是一个陌生的个人邮箱地址；没有名称的发件人
    是常见的垃圾邮件特征之一。已经写了名称（`名称 <地址>`）就原样保留。
    """
    name, addr = parseaddr(sender)
    if name or not addr:
        return sender
    return formataddr((DISPLAY_NAME, addr))


class ConsoleSender:
    """只把验证码写进日志。"""

    def send_code(self, to: str, code: str, ttl_minutes: int) -> None:
        log.warning("[console 发信器，未真正发送] 收件人 %s 验证码 %s（%d 分钟内有效）",
                    to, code, ttl_minutes)


class ResendSender:
    def __init__(self, api_key: str, sender: str, url: str):
        self.api_key = api_key
        self.sender = sender
        self.url = url

    def send_code(self, to: str, code: str, ttl_minutes: int) -> None:
        subject, body = compose(code, ttl_minutes)
        payload = json.dumps({"from": self.sender, "to": [to],
                              "subject": subject, "text": body}).encode()
        req = urllib.request.Request(self.url, data=payload, method="POST", headers={
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            # Resend 前面的 Cloudflare 会拦 urllib 默认的 User-Agent（error 1010）
            "User-Agent": "pinyintone-backend",
        })
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:   # noqa: S310（固定地址）
                resp.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read()[:300].decode(errors="replace")
            log.error("Resend 拒收：HTTP %s %s", exc.code, detail)
            raise EmailSendFailed(f"HTTP {exc.code}") from exc
        except OSError as exc:
            log.error("连不上 Resend：%s", exc)
            raise EmailSendFailed(str(exc)) from exc


class SMTPSender:
    def __init__(self, host: str, port: int, username: str, password: str,
                 security: str, sender: str):
        self.host, self.port = host, port
        self.username, self.password = username, password
        self.security = security
        self.sender = sender

    def send_code(self, to: str, code: str, ttl_minutes: int) -> None:
        subject, body = compose(code, ttl_minutes)
        msg = EmailMessage()
        msg["From"] = self.sender
        msg["To"] = to
        msg["Subject"] = subject
        # 缺 Date / Message-ID 的邮件更容易被判成垃圾邮件；Message-ID 用发件地址的域名
        msg["Date"] = formatdate(usegmt=True)
        domain = parseaddr(self.sender)[1].rpartition("@")[2] or None
        msg["Message-ID"] = make_msgid(domain=domain)
        msg.set_content(body)
        context = ssl.create_default_context()
        try:
            if self.security == "ssl":
                server = smtplib.SMTP_SSL(self.host, self.port, timeout=10, context=context)
            else:
                server = smtplib.SMTP(self.host, self.port, timeout=10)
            with server:
                if self.security == "starttls":
                    server.starttls(context=context)
                if self.username:
                    server.login(self.username, self.password)
                server.send_message(msg)
        except (smtplib.SMTPException, OSError) as exc:
            log.error("SMTP 发信失败：%s", exc)
            raise EmailSendFailed(str(exc)) from exc


def _console() -> EmailSender:
    if settings.is_production:
        raise EmailNotConfigured("生产环境不能用 console 发信器")
    return ConsoleSender()


def _resend() -> EmailSender:
    missing = [n for n, v in (("RESEND_API_KEY", settings.resend_api_key),
                              ("EMAIL_FROM", settings.email_from)) if not v.strip()]
    if missing:
        raise EmailNotConfigured(f"缺少 {', '.join(missing)}")
    return ResendSender(settings.resend_api_key.strip(),
                        with_display_name(settings.email_from.strip()), settings.resend_api_url)


def _smtp() -> EmailSender:
    missing = [n for n, v in (("SMTP_HOST", settings.smtp_host),
                              ("EMAIL_FROM", settings.email_from)) if not v.strip()]
    if missing:
        raise EmailNotConfigured(f"缺少 {', '.join(missing)}")
    security = settings.smtp_security.strip().lower()
    if security not in ("ssl", "starttls"):
        raise EmailNotConfigured("SMTP_SECURITY 须为 ssl 或 starttls")
    return SMTPSender(settings.smtp_host.strip(), settings.smtp_port, settings.smtp_username,
                      settings.smtp_password, security,
                      with_display_name(settings.email_from.strip()))


_FACTORIES = {"console": _console, "resend": _resend, "smtp": _smtp}


def get_sender() -> EmailSender:
    """按当前配置取发信器。没配好抛 `EmailNotConfigured`，**不会**退回到 console。"""
    name = settings.email_sender.strip().lower()
    if not name:
        if settings.is_production:
            raise EmailNotConfigured("生产环境须设置 EMAIL_SENDER")
        name = "console"
    factory = _FACTORIES.get(name)
    if factory is None:
        raise EmailNotConfigured(f"EMAIL_SENDER 须为 {list(_FACTORIES)} 之一")
    return factory()
