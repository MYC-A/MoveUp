# Backlog

Последнее обновление: 2026-05-17

## Priority 0: локальный запуск

### TASK-0001: Нормализовать backend-зависимости

area: backend
status: done 2026-05-17

Создать `backend_project/requirements.txt` или `pyproject.toml`, проверить импорты и зафиксировать команды установки/запуска.

Acceptance:

- Fresh virtualenv ставит зависимости.
- `uvicorn main:app --reload` стартует из `backend_project`.
- Недостающие системные сервисы описаны явно.

### TASK-0002: Добавить локальные PostgreSQL и MinIO

area: backend
status: done 2026-05-17

Добавить Docker Compose или четкую инструкцию для PostgreSQL и MinIO.

Acceptance:

- PostgreSQL можно поднять локально.
- MinIO bucket описан или создается автоматически.
- Backend может создать таблицы при старте.

### TASK-0003: Централизовать Flutter API configuration

area: flutter
status: mostly done 2026-05-17

Заменить hardcoded API, WebSocket и media host строки на один слой конфигурации.

Acceptance:

- Android emulator может ходить в локальный backend через `10.0.2.2`.
- Desktop/web/iOS simulator могут ходить в `localhost`.
- Production URL остается доступен через config switch.

## Priority 1: безопасность и чистота репозитория

### TASK-0004: Убрать secrets и generated files из git

area: repo
status: partial

Вынести `.env` и API keys в безопасный локальный конфиг, добавить root `.gitignore`, удалить tracked generated files в отдельной осознанной cleanup-ветке.

Acceptance:

- `.env`, `__pycache__` и IDE files игнорируются.
- Есть безопасные `.env.example`.
- Production secrets не лежат в исходниках.

### TASK-0005: Вынести OpenRouteService key из Flutter source

area: flutter
status: done 2026-05-17

Использовать build-time configuration или backend proxy для построения маршрутов.

Acceptance:

- API key не hardcoded в Dart source.
- App still builds, route creation имеет документированный config.

## Priority 2: API и поведение

### TASK-0006: Убрать duplicate event participation route

area: backend
status: done 2026-05-17

`backend_project/app/event/routers_event.py` объявляет `POST /events/{event_id}/participate` дважды. Нужно оставить одну реализацию и проверить поведение.

Acceptance:

- Только один route отвечает за event participation.
- Текущий Flutter flow участия в событии работает.

### TASK-0007: Выровнять media URL contract

area: api-contract

Backend сейчас отдает `localhost:9000` media URLs, а Flutter переписывает их на production MinIO URLs в разных экранах.

Acceptance:

- Backend возвращает client-safe media URLs по окружению.
- Flutter больше не делает scattered string rewrites.

### TASK-0008: Добавить smoke tests

area: backend

Добавить базовые тесты для auth, current user, auth behavior feed route и формы event list.

Acceptance:

- Тесты запускаются локально.
- Test setup не требует production services.

## Priority 3: Flutter quality

### TASK-0009: Объявить direct Flutter dependencies

area: flutter
status: done 2026-05-17

Добавить прямые зависимости для пакетов, которые импортируются напрямую, но сейчас присутствуют транзитивно, например `path_provider` и `flutter_cache_manager`.

Acceptance:

- `flutter analyze` не ругается на dependency reference issues.
- `pubspec.yaml` отражает прямые imports.

### TASK-0010: Отделить experimental Flutter files от production code

area: flutter

Проверить `flutter_project/lib/test/` и файлы без `.dart`; осознанно перенести или удалить.

Acceptance:

- Production source tree имеет понятную структуру.
- Нет случайных imports из experimental copies.
