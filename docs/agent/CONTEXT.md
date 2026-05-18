# Контекст проекта

Последнее обновление: 2026-05-17

## Кратко

MoveUp - монорепозиторий с двумя активными модулями:

- `backend_project`: FastAPI backend с API, Jinja2 HTML-страницами, статикой, PostgreSQL-моделями, JWT cookie auth, MinIO-загрузкой изображений и WebSocket.
- `flutter_project`: Flutter-клиент для авторизации, ленты, событий, профилей, чатов, трекинга маршрутов, локального хранения маршрутов, карт и загрузки изображений.

Проект пока лучше держать одним репозиторием, потому что Flutter и backend сильно связаны API-контрактами.

## Карта backend

Точка входа:

- `backend_project/main.py`

Роутеры:

- `/auth`: `app/users/router_users.py`
- `/profile`: `app/lk/routes_profile.py`
- `/post`: `app/posts/routes_posts.py`
- `/events`: `app/event/routers_event.py`
- `/chat`: `app/chat/router.py`
- `/friends`: `app/friendship/routes_friends.py`

Слой данных:

- `app/db/base.py`: async SQLAlchemy engine/session, `Base.metadata.create_all` при старте.
- `app/dao/base.py`: общие DAO-хелперы.
- Доменные модели лежат рядом с фичами: users, posts, events, chat, follow.

Auth:

- JWT хранится и читается через cookie `users_access_token`.
- Flutter сохраняет access token в secure storage и вручную отправляет его в заголовке `Cookie`.

Media:

- Фото постов и аватары используют MinIO.
- Backend берет endpoint, credentials, bucket names и public URL MinIO из settings/env.
- Flutter использует `AppConfig` для API, WebSocket, media URL и OpenRouteService key.

Runtime backend:

- Запускать из `backend_project`, чтобы `app/static` и `app/templates` работали.
- Порт приложения по умолчанию: `8000`.
- Реальная строка подключения к БД: `DATABASE_URL`.

## Карта Flutter

Точка входа:

- `flutter_project/lib/main.dart`

Основные вкладки:

- Лента: `screens_api/feed_screen.dart`
- События: `screens_api/event_screen.dart`
- Профиль: `screens_api/profile_screen.dart`
- Чаты: `screens_api/ChatListScreen.dart`
- Трекер: `screens/LiveTrackerScreen.dart`

API-сервисы:

- Auth: `services_api/auth_service.dart`
- Posts: `services_api/post_service.dart`
- Events: `services_api/EventService.dart`
- Chat: `services_api/ChatService.dart`
- Profile/current user: `services_api/lk_service.dart`, `services_api/LkUsersService.dart`
- WebSocket helpers: `services_api/web_socket_channel.dart`

Локальные функции устройства:

- GPS tracking: `services/GpsService.dart`, `screens/LiveTrackerScreen.dart`
- Локальное хранение маршрутов: `services/StorageService.dart`
- UI истории маршрутов: `screens/RouteHistoryScreen.dart`, `screens/RouteDetailsScreen.dart`, `screens/RouteViewScreen.dart`

Runtime Flutter:

- Dart SDK constraint: `^3.6.0`.
- API base URL, WebSocket URL, media URL и OpenRouteService key читаются через `String.fromEnvironment` в `lib/config/app_config.dart`.
- Production URL оставлены как default в одном config-файле для совместимости.

## API-контракт

Основные endpoints, которые ожидает Flutter:

- `POST /auth/register/`
- `POST /auth/login/`
- `POST /auth/logout/`
- `GET /auth/current_user`
- `GET /post/feed`
- `POST /post/posts_create`
- `POST /post/posts/{post_id}/like`
- `POST /post/posts/{post_id}/create_comment`
- `GET /post/posts/{post_id}/comments`
- `GET /post/posts/{post_id}/details`
- `GET /events/`
- `POST /events/create`
- `POST /events/{event_id}/participate`
- `GET /profile/`
- `PUT /profile/`
- `GET /profile/followers`
- `GET /profile/following`
- `GET /chat/`
- `GET /chat/users_with_messages`
- `GET /chat/messages/{user_id}`
- `POST /chat/messages`
- `POST /chat/group_chats`

WebSockets:

- `/post/ws/feed`
- `/post/ws/post/{post_id}`
- `/chat/ws/{user_id}`

## Текущие риски

- Старые secrets и сгенерированные файлы уже отслеживаются git; `.gitignore` добавлен, но tracked cleanup остается отдельным шагом.
- Есть экспериментальные копии файлов.
- Flutter SDK отсутствует в текущем контейнере, поэтому Flutter checks нужно запускать локально или в среде с Flutter.
