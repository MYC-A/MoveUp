# Code Map

Дата актуализации: 2026-06-01.

## Backend boot

- Entry point: `backend_project/main.py`.
- On startup: `app.db.base.init_db()` делает `Base.metadata.create_all()` и затем `ensure_schema_compatibility()`.
- CORS берется из `ALLOWED_ORIGINS`; если там `*`, `allow_credentials` выключается.
- Static files: `/static` -> `backend_project/app/static`.
- Routers:
  - `/auth` -> `app/users/router_users.py`.
  - `/chat` -> `app/chat/router.py`.
  - `/post` -> `app/posts/routes_posts.py`.
  - `/profile` -> `app/lk/routes_profile.py`.
  - `/profile/profile/notifications` фактически получается из `routes_notifications.py` (`prefix=/profile` + route `/profile/notifications`).
  - `/friends` -> `app/friendship/routes_friends.py`.
  - `/events` -> `app/event/routers_event.py`.
  - `/push` -> `app/push/router.py`.

## Backend data model

- User/profile: `app/users/models_user.py`.
  - `User`: email, username, full_name, bio, avatar_url, city, weight, height, verification fields, counters.
- Follow graph: `app/models/follow.py`.
- Posts: `app/posts/models_posts.py`, `models_posts_comments.py`, `models_posts_like.py`.
  - `Post`: content, distance, duration, city, route_data JSON, counters, created_at.
  - `PostPhoto`: MinIO URL per post.
  - `Comment`: post_id, user_id, content, created_at.
- Events: `app/event/models_event.py`.
  - `Event`: city, time range, available_seats, route_data JSON, optional group_chat_id, group_chat_enabled.
  - `EventParticipant`: approved status (`AWAITS`, `APPROVED`, `DENIED`), `is_new`, `status_changed`.
  - `UserNotification`: persistent event updates, used for deleted/cancelled event notifications.
- Chat: `app/chat/models.py`.
  - `Message`: personal message, currently no `created_at` column.
  - `GroupChat`, `group_chat_participants`, `GroupMessage`, `GroupMessageReadStatus`.
- Push: `app/push/models.py`.
  - `PushToken`: token, platform, optional device_id, active flag.

## Flutter boot

- Entry point: `flutter_project/lib/main.dart`.
- Startup:
  - initializes Russian date formatting;
  - initializes optional Firebase/FCM push;
  - configures notification tap navigation;
  - starts `MaterialApp` with `SplashScreen`.
- Main tabs in `MainScreen` use `IndexedStack`:
  - `FeedScreen`;
  - `EventScreen`;
  - `ProfileScreen`;
  - `ChatListScreen`;
  - `LiveTrackerScreen`.
- Main screen polls total unread chat count every 15 seconds.
- `ChatListScreen` also polls chat overview every 15 seconds while chat tab is active.

## Flutter config and env

- `flutter_project/lib/config/app_config.dart`:
  - `API_BASE_URL`, default `http://91.200.84.206/api`.
  - `WS_BASE_URL`, default `ws://91.200.84.206/api`.
  - `MEDIA_BASE_URL`, default `http://91.200.84.206/minio`.
  - `OPEN_ROUTE_API_KEY`, default empty.
  - `normalizeMediaUrl()` replaces local MinIO URLs with configured media base.

## Flutter services

- `AuthService`: register, verify email, resend code, login, refresh, logout, current user id.
- `Api`: thin HTTP wrapper with 20 second timeout and `ApiException` conversion.
- `PostService`: feed, like, delete post, comments, post details, create multipart post.
- `WebSocketService`: feed/post WebSocket with reconnect/backoff.
- `LkService`: own profile, profile update, notifications, own events/applications/participants.
- `LkUsersService`: other user profile, posts, followers/following, follow/unfollow.
- `EventService`: event list/cities/server time/participation/create/delete and OpenRouteService route building.
- `ChatService`: chat overview, personal/group messages, unread counters, group management, chat WebSocket.
- `PushNotificationService`: optional Firebase Messaging, local notifications, notification tap navigation.
- `StorageService`: local SQLite route storage, downloaded route dedupe through `source_post_id`.
- `GeocodingService`: Nominatim search/reverse city.

## Main Flutter screens

- Auth:
  - `SplashScreen`: checks cached/current auth and opens main/login.
  - `login_screen.dart`, `register_screen.dart`, `verify_email_screen.dart`.
- Feed:
  - `feed_screen.dart`: pagination, create post actions, feed WebSocket, MapController lifecycle.
  - `widgets/feed/post_item.dart`: post card, route preview, photos, comments sheet trigger, save/download/delete actions.
  - `widgets/post_comments_sheet.dart`: bottom sheet comments UI.
  - `PostDetails_screen.dart`: legacy full post details screen; kept for now.
- Events:
  - `event_screen.dart`: events list, filters, inline map previews, participation controls.
  - `CreateEventScreen.dart`: city autocomplete, route drawing/optimization, 200 km client limit.
  - `EventDetailsScreen.dart`, `EventApplicationsScreen.dart`, `OrganizerEvents_screen.dart`.
- Profile:
  - `profile_screen.dart`: own profile, hero, stats, notifications, own posts/events.
  - `edit_profile_screen.dart`: single profile edit screen for bio/avatar/body fields/password.
  - `UserProfiles.dart`, followers/following modals.
- Chat:
  - `ChatListScreen.dart`: personal/group chat list with avatars and unread badges.
  - `ChatScreen.dart`: personal chat, pagination, WebSocket receive, mark read.
  - `GroupChatScreen.dart`: group chat, participants, add participant, mark read.
- Routes/tracker:
  - `LiveTrackerScreen.dart`: GPS tracking, smoothing/filtering, save route.
  - `RouteHistoryScreen.dart`: saved/downloaded routes list, mini map previews.
  - `RouteDetailsScreen.dart`: edit route name/description, run route, local photos for own routes only.
  - `RouteViewScreen.dart`: follow/view a saved route.

## Local infrastructure

- `docker-compose.yml` starts PostgreSQL 16 on local port `5433` and MinIO on `9000/9001`.
- `backend_project/.env.example` targets that compose setup.
- Devcontainer files currently use a plain base image; Flutter/Python tooling is in `.codex-work/` for this workspace.

## Current generated docs

- `project_context.md`: dependencies and commands.
- `checks.md`: current verification status.
- `recent_changes.md`: recent feature/fix summary.
- `backlog.md`: prioritized risks.
- `audit_2026-06-01.md`: latest detailed audit.
- `api_contracts.md`: backend endpoints mapped to Flutter services and known contract risks.
