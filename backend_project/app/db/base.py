from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy import text
from app.core.config import settings

# Создаем асинхронный движок
engine = create_async_engine(
    settings.DATABASE_URL,  # Используем асинхронный URL (например, postgresql+asyncpg://...)
    echo=False  # Логирование SQL-запросов (опционально)
)

# Создаем фабрику асинхронных сессий
async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,  # Указываем, что сессии будут асинхронными
    expire_on_commit=False  # Отключаем автоматическое истечение объектов после commit
)

# Базовый класс для моделей
Base = declarative_base()

# Функция для получения асинхронной сессии
async def get_db():
    db = async_session_maker()
    try:
        yield db
    finally:
        await db.close()


async def init_db():
    async with engine.begin() as conn:
        # Создаем все таблицы, если они отсутствуют
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_compatibility(conn)


async def ensure_schema_compatibility(conn):
    # Проект пока живет без Alembic, поэтому держим маленькие безопасные
    # добавления колонок для уже созданных локальных баз.
    dialect = conn.dialect.name

    if dialect == "postgresql":
        await conn.execute(text("ALTER TABLE events ADD COLUMN IF NOT EXISTS city VARCHAR"))
        await conn.execute(text(
            "ALTER TABLE events ADD COLUMN IF NOT EXISTS group_chat_enabled "
            "BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS city VARCHAR"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS weight DOUBLE PRECISION"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS height DOUBLE PRECISION"))
        return

    if dialect == "sqlite":
        columns = await conn.execute(text("PRAGMA table_info(events)"))
        column_names = {row[1] for row in columns.fetchall()}
        if "city" not in column_names:
            await conn.execute(text("ALTER TABLE events ADD COLUMN city VARCHAR"))
        if "group_chat_enabled" not in column_names:
            await conn.execute(text(
                "ALTER TABLE events ADD COLUMN group_chat_enabled "
                "BOOLEAN NOT NULL DEFAULT 0"
            ))

        user_columns = await conn.execute(text("PRAGMA table_info(users)"))
        user_column_names = {row[1] for row in user_columns.fetchall()}
        if "city" not in user_column_names:
            await conn.execute(text("ALTER TABLE users ADD COLUMN city VARCHAR"))
        if "weight" not in user_column_names:
            await conn.execute(text("ALTER TABLE users ADD COLUMN weight REAL"))
        if "height" not in user_column_names:
            await conn.execute(text("ALTER TABLE users ADD COLUMN height REAL"))
