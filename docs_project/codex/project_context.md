# Контекст проекта

Дата актуализации: 2026-06-01.

## Структура

- `backend_project/` - FastAPI backend.
- `backend_project/app/users/` - регистрация, вход, refresh/access token, cookie auth.
- `backend_project/app/lk/` - профиль, аватары, подписки, личный кабинет, мои события/заявки.
- `backend_project/app/lk/routes_notifications.py` - уведомления по заявкам, изменениям статуса и системным event updates.
- `backend_project/app/event/` - события, участники, схемы события и route validation.
- `backend_project/app/posts/` - лента, посты, лайки, комментарии, WebSocket ленты.
- `backend_project/app/chat/` - личные и групповые чаты, unread counts, WebSocket.
- `backend_project/app/push/` - FCM push-token endpoints и push delivery.
- `backend_project/migrations/` - Alembic scaffold; версий миграций пока нет, только `.gitkeep`.
- `backend_project/tests/` - pytest-набор: auth schema, event schema, security, uploads.
- `flutter_project/` - Flutter-клиент.
- `flutter_project/lib/screens_api/` - API-экраны: лента, мероприятия, профиль, чаты.
- `flutter_project/lib/widgets/feed/post_item.dart` - карточка поста и превью карты маршрута в ленте.
- `flutter_project/lib/widgets/common/osm_tile_layer.dart` - единый OSM tile layer с кешированием.
- `flutter_project/lib/services/StorageService.dart` - локальная SQLite-база маршрутов.
- `flutter_project/lib/services_api/` - HTTP/WebSocket/push сервисы для backend.
- `docs_project/codex/` - tracked рабочие заметки Codex.
- `.codex-work/` - локальные инструменты в workspace: Flutter SDK и backend venv.

## Локальные версии инструментов

- Flutter `3.27.1`, Dart `3.6.0` (`.codex-work/flutter`).
- Backend venv: Python `3.12.3` (`.codex-work/backend-venv`).
- CI backend использует Python `3.11`.
- CI Flutter использует Flutter `3.27.1` stable.

## Зависимости Flutter

Ключевые зависимости из `flutter_project/pubspec.yaml`:

- `flutter_map: ^7.0.2`.
- `latlong2: ^0.9.0`.
- `geolocator: ^10.0.0`.
- `sqflite: ^2.2.0+4`.
- `visibility_detector: ^0.4.0+2`.
- `cached_network_image: ^3.4.1`.
- `flutter_cache_manager: ^3.4.1`.
- `web_socket_channel: ^3.0.1`.
- `firebase_core: ^4.9.0`.
- `firebase_messaging: ^16.2.2`.
- `flutter_local_notifications: ^19.5.0`.
- `intl: any` - версию пинит `flutter_localizations`.

## Зависимости backend

Ключевые зависимости из `backend_project/requirements.txt`:

- `fastapi==0.115.6`.
- `uvicorn[standard]==0.32.1`.
- `sqlalchemy[asyncio]==2.0.36`.
- `alembic==1.14.0`.
- `asyncpg==0.30.0`.
- `pydantic==2.10.3`.
- `pydantic-settings==2.7.0`.
- `minio==7.2.12`.
- `firebase-admin==6.6.0`.
- Tests: `pytest==8.3.4`, `pytest-asyncio==0.25.0`, `httpx==0.28.1`.

## Полезные команды

Flutter:

```bash
cd flutter_project
../.codex-work/flutter/bin/flutter analyze
../.codex-work/flutter/bin/flutter test
../.codex-work/flutter/bin/dart analyze lib/widgets/feed/post_item.dart
```

Backend:

```bash
cd backend_project
../.codex-work/backend-venv/bin/python -m compileall app
../.codex-work/backend-venv/bin/python -m pytest
```

Версии:

```bash
cd flutter_project
../.codex-work/flutter/bin/flutter --version

cd backend_project
../.codex-work/backend-venv/bin/python --version
```

## Tracked docs for future work

- `README.md` - порядок чтения рабочей памяти.
- `code_map.md` - карта модулей, экранов, сервисов, моделей и локальной инфраструктуры.
- `api_contracts.md` - backend endpoints -> Flutter services и известные contract gaps.
- `checks.md` - последние проверки и warnings.
- `backlog.md` - приоритетные риски и задачи.
- `recent_changes.md` - что уже исправлено/добавлено.
- `audit_2026-06-01.md` - подробный срез после последних доработок.
