# Контекст проекта

## Структура

- `flutter_project/` - Flutter-приложение.
- `flutter_project/lib/screens_api/` - основные API-экраны: лента, мероприятия, профиль, детали поста.
- `flutter_project/lib/screens/` - экраны маршрутов, трекера и локальной истории.
- `flutter_project/lib/services_api/` - HTTP/WebSocket-сервисы для backend API.
- `flutter_project/lib/services/StorageService.dart` - локальная SQLite-база маршрутов.
- `backend_project/` - FastAPI backend.
- `backend_project/app/event/` - мероприятия, участники, схемы события.
- `backend_project/app/lk/` - профиль, заявки, уведомления, личный кабинет.
- `backend_project/app/chat/` - личные и групповые чаты.
- `docs_project/` - проектные заметки.
- `.codex-work/` - локальные инструменты, созданные для работы Codex: Flutter SDK и backend venv.

## Версии и зависимости

Flutter/Dart:

- Dart SDK constraint: `^3.6.0`.
- `flutter_map: ^7.0.2`.
- `latlong2: ^0.9.0`.
- `geolocator: ^10.0.0`.
- `sqflite: ^2.2.0+4`.
- `visibility_detector: ^0.4.0+2`.
- `cached_network_image: ^3.4.1`.
- `web_socket_channel: ^3.0.1`.
- Firebase packages указаны в `flutter_project/pubspec.yaml`.

Backend:

- `fastapi==0.115.6`.
- `uvicorn[standard]==0.32.1`.
- `sqlalchemy[asyncio]==2.0.36`.
- `asyncpg==0.30.0`.
- `pydantic==2.10.3`.
- `minio==7.2.12`.
- `firebase-admin==6.6.0`.

## Полезные команды

Flutter:

```bash
cd flutter_project
../.codex-work/flutter/bin/dart format lib/screens_api/feed_screen.dart
../.codex-work/flutter/bin/dart analyze lib/screens_api/feed_screen.dart
../.codex-work/flutter/bin/flutter test
../.codex-work/flutter/bin/flutter analyze
```

Backend:

```bash
cd backend_project
../.codex-work/backend-venv/bin/python -m compileall app
```

Проверка схемы создания события с маршрутом:

```bash
cd backend_project
../.codex-work/backend-venv/bin/python - <<'PYCHECK'
from app.event.schemas_event import EventCreate, EventType
EventCreate(
    title='test',
    event_type=EventType.RUNNING,
    difficulty='новичок',
    max_participants=5,
    city='Москва',
    route_data=[
        {'latitude': 55.7558, 'longitude': 37.6173},
        {'latitude': 55.7560, 'longitude': 37.6180},
    ],
)
print('ok')
PYCHECK
```
