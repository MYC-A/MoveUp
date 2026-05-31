# Миграции БД (Alembic)

Каркас Alembic для управления схемой. URL берётся из `settings.DATABASE_URL`,
`target_metadata` — из `Base.metadata` (см. `env.py`).

## Первый запуск
```bash
cd backend_project
pip install -r requirements.txt
# Поднять БД (docker compose up -d postgres) и задать DATABASE_URL в .env
alembic revision --autogenerate -m "baseline"   # сгенерировать первую миграцию из моделей
alembic upgrade head                              # применить
```

## Дальше
При изменении моделей:
```bash
alembic revision --autogenerate -m "что изменилось"
alembic upgrade head
```

## Переходный период
Сейчас схема также создаётся через `create_all()` + `ensure_schema_compatibility()`
([app/db/base.py](../app/db/base.py)) — это рантайм-страховка для уже существующих
локальных баз. После того как Alembic-миграции станут основным механизмом
(применён baseline на всех окружениях), `ensure_schema_compatibility` можно убрать,
а `create_all` оставить только для тестов.
