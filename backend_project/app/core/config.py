# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", "app/.env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5433/runner_db"
    DB_USER: str = "postgres"
    DB_PASSWORD: str = "postgres"
    DB_HOST: str = "localhost"
    DB_PORT: str = "5433"

    SECRET_KEY: str = "change-me-local-secret"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_PUBLIC_URL: str = "http://localhost:9000"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minioadmin"
    MINIO_BUCKET_NAME: str = "photos"
    MINIO_POSTS_BUCKET_NAME: str = "posts"
    OPEN_ROUTE_API_KEY: str = ""



settings = Settings()

def get_db_url():
    return settings.DATABASE_URL

def get_auth_data():
    return {"secret_key": settings.SECRET_KEY, "algorithm": settings.ALGORITHM}
