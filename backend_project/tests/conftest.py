"""Общая настройка тестов.

Подставляем безопасные значения обязательных настроек ДО импорта приложения,
чтобы `Settings()` в app.core.config грузился без реального .env, БД и MinIO.
Реальные переменные окружения (если заданы) имеют приоритет.
"""
import os

os.environ.setdefault(
    "DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/test"
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")
os.environ.setdefault("ALGORITHM", "HS256")
os.environ.setdefault("MINIO_ENDPOINT", "localhost:9000")
os.environ.setdefault("MINIO_PUBLIC_URL", "http://localhost:9000")
os.environ.setdefault("MINIO_ACCESS_KEY", "test")
os.environ.setdefault("MINIO_SECRET_KEY", "test")
os.environ.setdefault("MINIO_BUCKET_NAME", "photos")
os.environ.setdefault("MINIO_POSTS_BUCKET_NAME", "posts")
os.environ.setdefault("OPEN_ROUTE_API_KEY", "")
