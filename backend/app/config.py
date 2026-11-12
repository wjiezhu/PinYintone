from pydantic_settings import BaseSettings, SettingsConfigDict


def _split(value: str) -> list[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./pinyintone.db"
    jwt_secret: str = "dev-secret-change-me-in-production-0123456789"
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 720  # 30 天

    # ── 学生登录凭证的服务端校验（identity.py）──
    # 逗号分隔。Apple identityToken 的 aud 是 App 的 bundle id。
    # 留空 = 无法校验 Apple 凭证（带了 token 的登录按「未配置」处理，见 identity.py）
    apple_bundle_ids: str = ""
    # 逗号分隔。Google ID token 的 aud：Android 用 Credential Manager 时是
    # 传给 serverClientId 的那个 **Web** client id；也可同时列 Android client id
    google_client_ids: str = ""
    # 过渡期开关：线上已装的旧版 iOS 不上传 identityToken。
    # 开着时，没带 token 的 Apple 登录照旧放行（记日志并在 users.legacy_login_at 留痕）。
    # 什么时候关由人决定，不在代码里定日期。
    allow_legacy_unverified_apple: bool = True
    # 公钥缓存时长（秒）。遇到不认识的 kid 会提前刷新（有最短间隔）
    jwks_cache_seconds: int = 6 * 3600

    # ── 运行环境 ──
    # development | production。留空时按数据库判断：PostgreSQL = 生产，其余 = 开发。
    # 生产环境下发信器没配好时，邮箱登录直接 503，不会退回到只写日志的 console
    app_env: str = ""

    # ── 邮箱验证码登录（email_login.py / email_sender.py）──
    # console（只写日志，开发与测试用）| resend | smtp。留空 = 开发环境用 console、生产环境 503
    email_sender: str = ""
    # 发件人，如 "Pinyintone <login@mail.example.com>"；域名须已在发信服务商处验证
    email_from: str = ""
    resend_api_key: str = ""
    resend_api_url: str = "https://api.resend.com/emails"
    # smtp：阿里云邮件推送、Amazon SES 等都提供 SMTP 接口，换服务商只改这几项
    smtp_host: str = ""
    smtp_port: int = 465
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_security: str = "ssl"          # ssl（465）| starttls（587）
    # 频率限制（每小时）。同一 IP 的上限要留余量：一个教室的学生常共用一个出口 IP
    email_code_per_email_per_hour: int = 5
    email_code_per_ip_per_hour: int = 30
    # 取客户端 IP 时信任几层反向代理（X-Forwarded-For 从右往左数）。
    # Railway / Render 前面各有一层代理，取 1；直接对外暴露时取 0
    trusted_proxy_hops: int = 1

    # ── Android 直接分发的新版本检查（routers/app_version.py）──
    # 安装包不上 Google Play，由研究者把下载地址发给参与者。App 启动时查一次：
    # 有新版本给可关闭的提示，低于最低支持版本提示必须更新。版本号用 versionCode（整数）比较。
    # latest = 0 或下载地址留空 = 没有发布信息，App 什么也不提示
    android_latest_version_code: int = 0
    android_latest_version_name: str = ""
    android_min_version_code: int = 0
    # 必须是 https：App 只把它交给系统浏览器打开，App 内不下载、不安装
    android_download_url: str = ""
    # 更新说明，按界面语言各写一条（可只写一部分；App 依次退到 en、zh）
    android_release_notes_zh: str = ""
    android_release_notes_en: str = ""
    android_release_notes_fr: str = ""
    android_release_notes_ar: str = ""

    @property
    def is_production(self) -> bool:
        env = self.app_env.strip().lower()
        if env:
            return env in ("production", "prod")
        return self.database_url.startswith(("postgres://", "postgresql"))

    @property
    def apple_audiences(self) -> list[str]:
        return _split(self.apple_bundle_ids)

    @property
    def google_audiences(self) -> list[str]:
        return _split(self.google_client_ids)


settings = Settings()
