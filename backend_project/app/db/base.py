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
    # Значение enum нельзя добавлять в той же транзакции, где оно создаётся/
    # используется, поэтому делаем это отдельным автокоммит-соединением.
    await ensure_enum_values()


async def ensure_enum_values():
    """Идемпотентно добавляет недостающие значения PostgreSQL-enum для уже
    существующих баз (на свежей БД enum создаётся сразу со всеми значениями)."""
    if engine.dialect.name != "postgresql":
        # SQLite в dev хранит Enum как VARCHAR+CHECK; локальную базу проще
        # пересоздать, отдельная миграция не нужна.
        return
    try:
        async with engine.connect() as conn:
            await conn.execution_options(isolation_level="AUTOCOMMIT")
            await conn.execute(
                text("ALTER TYPE approvedtype ADD VALUE IF NOT EXISTS 'INVITED'")
            )
    except Exception as exc:  # pragma: no cover - не критично для запуска
        import logging
        logging.getLogger(__name__).warning(
            "Не удалось добавить значение enum 'INVITED' в approvedtype: %s", exc
        )


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
        await conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified "
            "BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        # Существующие аккаунты предшествуют подтверждению email — считаем
        # их подтверждёнными, чтобы не заблокировать вход.
        await conn.execute(text(
            "UPDATE users SET is_verified = TRUE WHERE is_verified = FALSE"
        ))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_code VARCHAR"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_code_expires TIMESTAMP"))
        await conn.execute(text("ALTER TABLE posts ADD COLUMN IF NOT EXISTS city VARCHAR"))
        await conn.execute(text("ALTER TABLE messages ADD COLUMN IF NOT EXISTS created_at TIMESTAMP"))
        await conn.execute(text("UPDATE messages SET created_at = NOW() WHERE created_at IS NULL"))
        # Индексы для ленты (сортировка по дате, фильтр по автору/подпискам).
        await conn.execute(text("CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC)"))
        await conn.execute(text("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)"))
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
        if "is_verified" not in user_column_names:
            await conn.execute(text(
                "ALTER TABLE users ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT 0"
            ))
            await conn.execute(text("UPDATE users SET is_verified = 1"))
        if "verification_code" not in user_column_names:
            await conn.execute(text("ALTER TABLE users ADD COLUMN verification_code VARCHAR"))
        if "verification_code_expires" not in user_column_names:
            await conn.execute(text("ALTER TABLE users ADD COLUMN verification_code_expires DATETIME"))

        post_columns = await conn.execute(text("PRAGMA table_info(posts)"))
        post_column_names = {row[1] for row in post_columns.fetchall()}
        if "city" not in post_column_names:
            await conn.execute(text("ALTER TABLE posts ADD COLUMN city VARCHAR"))

        message_columns = await conn.execute(text("PRAGMA table_info(messages)"))
        message_column_names = {row[1] for row in message_columns.fetchall()}
        if "created_at" not in message_column_names:
            await conn.execute(text("ALTER TABLE messages ADD COLUMN created_at DATETIME"))
            await conn.execute(text("UPDATE messages SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL"))

        await conn.execute(text("CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at)"))
        await conn.execute(text("CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)"))
