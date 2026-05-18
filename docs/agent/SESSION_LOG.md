# Session Log

## 2026-05-17: Bootstrap agent workspace

Запрос пользователя:

- Изучить проект.
- Создать базовую структуру `docs/agent/` и шаблон задач.
- Написать полезный root `README.md`.

Что найдено:

- Репозиторий является монорепозиторием с `backend_project` и `flutter_project`.
- Backend: FastAPI, роутеры auth/profile/posts/events/chat/friends.
- Backend использует async SQLAlchemy, PostgreSQL, JWT cookie auth, Jinja2 templates, static assets, MinIO image upload и WebSockets.
- Flutter: русская локаль, API-backed feed/events/profile/chats, GPS route tracking, local SQLite route storage, maps, image upload.
- Flutter сейчас смотрит на `http://91.200.84.206/api` и `ws://91.200.84.206/api`.
- Backend dependency file и Docker Compose отсутствуют.
- Есть hygiene issues: tracked `.env`, tracked `__pycache__`, tracked IDE files.

Создано/обновлено:

- `README.md`
- `docs/agent/README.md`
- `docs/agent/CONTEXT.md`
- `docs/agent/BACKLOG.md`
- `docs/agent/SESSION_LOG.md`
- `docs/agent/DECISIONS.md`
- `docs/agent/PROMPTS.md`
- `docs/agent/TASK_TEMPLATE.md`
- `docs/agent/tasks/README.md`

Следующий рекомендуемый шаг:

- Начать с `TASK-0001: Нормализовать backend-зависимости`, затем перейти к `TASK-0003: Централизовать Flutter API configuration`.

## 2026-05-17: Tech debt cleanup and backend smoke run

Что сделано:

- Добавлен root `.gitignore`.
- Добавлен `backend_project/requirements.txt`.
- Добавлен `backend_project/.env.example`.
- Добавлен `docker-compose.yml` для PostgreSQL и MinIO.
- Backend settings расширены для DB, MinIO и OpenRouteService через env.
- Убран import-time side effect: profile router больше не ходит в MinIO при импорте.
- Убран duplicate `POST /events/{event_id}/participate`.
- Убран duplicate `PUT /profile/`.
- OpenRouteService key вынесен из Flutter и backend static JS source.
- Добавлен `flutter_project/lib/config/app_config.dart`.
- Flutter API/WebSocket/media/OpenRoute настройки переведены на `AppConfig`.
- В `pubspec.yaml` добавлены direct dependencies `http`, `path_provider`, `flutter_cache_manager` и assets.

Проверки:

- `python -m venv .venv` в `backend_project`.
- `.venv/bin/pip install -r requirements.txt`.
- `.venv/bin/python -m compileall app main.py`.
- `.venv/bin/python -c "import main; print('main import ok')"`.
- `docker compose config`.
- `docker compose up -d postgres minio minio-init`.
- `.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000`.
- `GET /docs` -> 200.
- `GET /openapi.json` -> schema generated.
- `GET /events/?format=json` -> 200.

Ограничения:

- Flutter SDK и Dart CLI отсутствуют в текущем контейнере, поэтому `flutter analyze` и `flutter run` не запускались.
- Docker services оставлены поднятыми.
- Uvicorn после проверки остановлен.
- Старые tracked `.env`, `.idea`, `__pycache__` не удалялись из git history/working tree; для этого нужен отдельный cleanup шаг.

## 2026-05-17: Flutter desktop run attempt

Что сделано:

- В `/tmp/flutter` установлен временный Flutter SDK `3.41.9` stable с Dart `3.11.5`.
- `flutter pub get` успешно выполнен после обновления `intl` до `^0.20.2`, потому что `flutter_localizations` из SDK пинит `intl 0.20.2`.
- Для Linux desktop сборки установлены системные зависимости `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`.
- Исправлен Linux CMake: plugin targets теперь получают `APPLICATION_ID`, который требуется `flutter_secure_storage_linux`.

Проверки:

- `flutter analyze` запускается и находит 65 issues уровня warning/info. Критичных compile errors нет.
- `flutter build linux --debug` проходит успешно.
- `flutter run -d linux` собирает bundle `build/linux/x64/debug/bundle/flutter_application_1`, но запуск в текущем контейнере падает на `Gtk-WARNING: cannot open display`.
- `flutter run -d web-server` без эскалации не смог скачать Flutter Web SDK из-за restricted network. Повтор с эскалацией заблокирован лимитом текущей среды.

Итог:

- Flutter desktop проект компилируется в Linux debug bundle.
- Полный GUI-запуск нужно проверять в локальной среде с дисплеем, либо в контейнере с установленным `xvfb`.
