from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./pinyintone.db"
    jwt_secret: str = "dev-secret-change-me-in-production-0123456789"
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 720  # 30 天


settings = Settings()
