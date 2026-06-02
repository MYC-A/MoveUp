# MoveUp

MoveUp - мобильное приложение для бега, маршрутов, событий, постов и общения. Проект состоит из Flutter-клиента и FastAPI-backend.

Репозиторий оставлен как монорепозиторий: приложение и backend сильно связаны через авторизацию, API-контракты, посты, события, чаты, профили, маршруты и медиа.

## Структура

```text
MoveUp/
  backend_project/       FastAPI backend, HTML-шаблоны, статика, API-роуты
  flutter_project/       Flutter-приложение
```

## Модули проекта

Backend:

- `main.py`: точка входа FastAPI, CORS, статика, подключение роутеров, инициализация БД на старте.
- `app/users`: регистрация, вход, выход, текущий пользователь, JWT cookie auth.
- `app/lk`: профиль, аватар, подписчики/подписки, уведомления, события пользователя.
- `app/posts`: лента, создание постов, лайки, комментарии, детали поста, WebSocket ленты.
- `app/event`: создание событий, список/детали событий, участие, опциональное создание группового чата.
- `app/chat`: личные чаты, групповые чаты, счетчики непрочитанных, WebSocket-уведомления.
- `app/friendship`: подписка, отписка, проверка подписки.
- `app/static` и `app/templates`: браузерный HTML-интерфейс backend.

Flutter:

- `lib/main.dart`: точка входа, русская локаль, основные вкладки приложения.
- `lib/screens`: трекинг маршрутов и локальная история маршрутов.
- `lib/screens_api`: экраны, которые работают с backend API.
- `lib/services`: локальное хранилище и GPS-сервисы.
- `lib/services_api`: HTTP и WebSocket-клиенты для backend.
- `lib/models` и `lib/models_api`: локальные модели маршрутов и API-модели.

## Текущее состояние запуска

Backend сейчас ожидает:

- Python 3.11 или новее.
- PostgreSQL через `DATABASE_URL`.
- MinIO через `MINIO_ENDPOINT` для изображений постов и аватаров.
- Запуск из папки `backend_project`, чтобы пути `app/static` и `app/templates` резолвились корректно.

Flutter сейчас ожидает:

- Flutter SDK с Dart `^3.6.0`.
- Доступ в интернет для карт, удаленных изображений и OpenRouteService.
- API/WebSocket/media/OpenRoute настройки берутся из `lib/config/app_config.dart`.
- Для локального backend используются `--dart-define`.
- Push-уведомления сообщений опциональны и требуют Firebase/FCM настройки.

Важно: текущие production URL оставлены только как default в `AppConfig`, чтобы не сломать существующий запуск без параметров.

## Backend: локальный запуск

Из корня репозитория:

```bash
docker compose up -d postgres minio minio-init
```

Затем:

```bash
cd backend_project
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Backend будет доступен здесь:

```text
http://localhost:8000
http://localhost:8000/docs
```

Переменные окружения нужно вынести в локальный файл, который не коммитится. Сейчас настройки читаются через `pydantic-settings` с поддержкой `.env`.

Минимальный набор:

```text
DATABASE_URL=postgresql+asyncpg://USER:PASSWORD@HOST:PORT/DB_NAME
SECRET_KEY=your-random-local-secret
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
MINIO_ENDPOINT=localhost:9000
MINIO_PUBLIC_URL=http://localhost:9000
MINIO_ACCESS_KEY=your-minio-user
MINIO_SECRET_KEY=your-minio-password
MINIO_BUCKET_NAME=photos
MINIO_POSTS_BUCKET_NAME=posts
OPEN_ROUTE_API_KEY=

# Optional: system push notifications for chats.
FCM_ENABLED=false
FIREBASE_CREDENTIALS_PATH=./firebase-service-account.json
FCM_ANDROID_CHANNEL_ID=moveup_messages
```

## Flutter: локальный запуск

Из корня репозитория:

```bash
cd flutter_project
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000 \
  --dart-define=MEDIA_BASE_URL=http://10.0.2.2:9000 \
  --dart-define=OPEN_ROUTE_API_KEY=your-openroute-key
```

Для других платформ:

- iOS simulator, desktop, web local dev: `http://localhost:8000`
- Physical device: IP компьютера в локальной сети

Без `--dart-define` приложение использует production defaults из `AppConfig`.

## Push-уведомления сообщений

Для системных уведомлений используется FCM data-push + локальная Android notification карточка. Flutter показывает одну expandable карточку на диалог и держит максимум 3 видимые строки, чтобы поток сообщений не забивал шторку.

Что нужно для локальной проверки:

1. Создать Firebase Android app с package `com.example.flutter_application_1`.
2. Скачать service account json и положить вне git, например рядом с локальными секретами.
3. В `backend_project/.env` включить `FCM_ENABLED=true` и указать `FIREBASE_CREDENTIALS_PATH`.
4. Обновить backend-зависимости: `pip install -r requirements.txt`.
5. Запустить Flutter с Firebase `--dart-define`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000 \
  --dart-define=MEDIA_BASE_URL=http://10.0.2.2:9000 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=...
```

Если Firebase-параметры не заданы, push-сервис отключается без падения приложения.
