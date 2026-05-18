# TASK-0001: Tech Debt Bootstrap

Status: completed

Area: backend | flutter | repo | docs

Owner: agent

Created: 2026-05-17

## Проблема

Проект не имел воспроизводимого локального запуска backend, часть настроек и secrets была зашита в код, Flutter держал API/WebSocket/media URLs в разных сервисах, а backend содержал duplicate routes.

## Цель

Сделать базовый локальный запуск backend воспроизводимым и убрать самые очевидные hardcoded config/duplicate route долги.

## Сделано

- Добавлены `.gitignore`, backend requirements, `.env.example`, Docker Compose.
- Backend MinIO/OpenRoute настройки переведены на env.
- Flutter получил единый `AppConfig`.
- Убраны duplicate routes: `POST /events/{event_id}/participate` и `PUT /profile/`.
- Убран OpenRouteService key из source.
- Backend smoke-run прошел с PostgreSQL и MinIO из Docker.

## Затронутые файлы

- `.gitignore`
- `docker-compose.yml`
- `README.md`
- `backend_project/requirements.txt`
- `backend_project/.env.example`
- `backend_project/app/core/config.py`
- `backend_project/app/event/routers_event.py`
- `backend_project/app/lk/routes_profile.py`
- `backend_project/app/posts/routes_posts.py`
- `backend_project/app/static/js/create_event.js`
- `backend_project/app/templates/create_event.html`
- `backend_project/test/create_event_1.js`
- `flutter_project/lib/config/app_config.dart`
- `flutter_project/lib/services_api/*.dart`
- `flutter_project/lib/screens_api/*.dart`
- `flutter_project/lib/widgets/UserPosts.dart`
- `flutter_project/linux/CMakeLists.txt`
- `flutter_project/pubspec.yaml`
- `flutter_project/pubspec.lock`
- `docs/agent/*`

## Проверка

Команды:

```bash
cd backend_project
python -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m compileall app main.py
.venv/bin/python -c "import main; print('main import ok')"
cd ..
docker compose config
docker compose up -d postgres minio minio-init
cd backend_project
.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
curl http://127.0.0.1:8000/docs
curl http://127.0.0.1:8000/openapi.json
curl "http://127.0.0.1:8000/events/?format=json"
cd ../flutter_project
/tmp/flutter/bin/flutter pub get
HOME=/tmp/flutter-home /tmp/flutter/bin/flutter analyze
HOME=/tmp/flutter-home /tmp/flutter/bin/flutter build linux --debug \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=WS_BASE_URL=ws://127.0.0.1:8000 \
  --dart-define=MEDIA_BASE_URL=http://127.0.0.1:9000 \
  --dart-define=OPEN_ROUTE_API_KEY=
```

Результаты:

- Python compile passed.
- `import main` passed.
- Docker PostgreSQL and MinIO healthy.
- Backend startup passed.
- `/docs` returned 200.
- `/openapi.json` generated.
- `/events/?format=json` returned 200.
- `flutter pub get` passed.
- `flutter analyze` ran and reported 65 warning/info issues.
- `flutter build linux --debug` passed.
- `flutter run -d linux` built the bundle, then stopped at `Gtk-WARNING: cannot open display` because the container has no GUI display.

## Открытые вопросы

- Нужно локально проверить GUI-запуск Flutter на машине с дисплеем, либо повторить в контейнере с `xvfb`.
- Нужно отдельной задачей разобрать 65 `flutter analyze` warning/info issues.
- Нужно отдельной задачей убрать tracked `.env`, `.idea`, `__pycache__`.
- Можно дополнительно свернуть media URL normalization в один helper во всех UI-файлах.
