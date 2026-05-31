# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str

    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    # Срок жизни access-токена (cookie-аутентификация). Сокращён с ~года до
    # 2 недель; долгие сессии продлеваются refresh-токеном (/auth/refresh).
    ACCESS_TOKEN_EXPIRE_DAYS: int = 14
    # Refresh-токен живёт дольше и позволяет получить новый access без
    # повторного ввода пароля.
    REFRESH_TOKEN_EXPIRE_DAYS: int = 60

    MINIO_ENDPOINT: str
    MINIO_PUBLIC_URL: str
    MINIO_ACCESS_KEY: str
    MINIO_SECRET_KEY: str
    MINIO_BUCKET_NAME: str
    MINIO_POSTS_BUCKET_NAME: str
    OPEN_ROUTE_API_KEY: str

    FCM_ENABLED: bool = False
    FIREBASE_CREDENTIALS_PATH: str = ""
    FCM_ANDROID_CHANNEL_ID: str = "moveup_messages"

    # Подтверждение email при регистрации. Если EMAIL_ENABLED=false или SMTP не
    # настроен — код всё равно генерируется, но не отправляется (пишется в лог),
    # чтобы фича работала в dev без почтового сервера. В проде задайте SMTP_*.
    EMAIL_ENABLED: bool = False
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM: str = "no-reply@moveup.app"
    SMTP_USE_TLS: bool = True

    # Список разрешённых CORS-источников через запятую. По умолчанию "*"
    # (сохраняет текущее поведение); в проде стоит указать явные домены,
    # т.к. "*" вместе с cookie-аутентификацией небезопасен.
    ALLOWED_ORIGINS: str = "*"

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]


settings = Settings()

def get_db_url():
    return settings.DATABASE_URL

def get_auth_data():
    return {"secret_key": settings.SECRET_KEY, "algorithm": settings.ALGORITHM}
