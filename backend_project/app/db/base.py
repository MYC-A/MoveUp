from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import sessionmaker, declarative_base
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