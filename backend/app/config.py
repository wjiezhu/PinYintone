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

    @property
    def apple_audiences(self) -> list[str]:
        return _split(self.apple_bundle_ids)

    @property
    def google_audiences(self) -> list[str]:
        return _split(self.google_client_ids)


settings = Settings()
