"""Alembic env (async). URL берётся из настроек приложения, target_metadata —
из Base.metadata. Импортируем модели, чтобы они зарегистрировались в метаданных
и попадали в autogenerate.

Использование (после `pip install -r requirements.txt`):
  alembic revision --autogenerate -m "baseline"   # создать первую миграцию
  alembic upgrade head                              # применить
"""
import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

from app.core.config import settings
from app.db.base import Base

# Импорт модулей с моделями — чтобы все таблицы оказались в Base.metadata.
import app.users.models_user  # noqa: F401
import app.posts.models_posts  # noqa: F401
import app.posts.models_posts_like  # noqa: F401
import app.posts.models_posts_comments  # noqa: F401
import app.event.models_event  # noqa: F401
import app.chat.models  # noqa: F401
import app.models.follow  # noqa: F401
import app.push.models  # noqa: F401

config = context.config
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
