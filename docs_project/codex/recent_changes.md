# Последние исправления и доработки

Дата актуализации: 2026-06-01.

## Backend

- Добавлен pytest-набор (`27 passed`).
- Добавлен Alembic scaffold (`backend_project/migrations`), но versions пока пустые.
- Уведомления вынесены из `routes_profile.py` в `routes_notifications.py`.
- Уведомления по заявкам берут название события через join к `Event`, а не через список событий организатора.
- Добавлены persistent `UserNotification`/`event_updates` для системных уведомлений, которые переживают удаление события.
- В `EventCreate` проверяются:
  - координаты route point;
  - максимальная длина маршрута 200 км;
  - `max_participants >= 1`;
  - `end_time > start_time`.
- Добавлены настройки refresh/access token lifetime, optional email и CORS origins в config.

## Flutter: лента

- `PostItem` вынесен в `flutter_project/lib/widgets/feed/post_item.dart`.
- Карта маршрута в посте живет в `_PostRouteMap`.
- Точки маршрута кешируются, preview polyline прореживается до 150 точек.
- `VisibilityDetector` вызывает zoom один раз при появлении карты.
- `FlutterMap` завернут в `RepaintBoundary`.
- Используется общий `osmTileLayer()` с кешированием тайлов.
- В ленте добавлена защита от дублей при пагинации, обработка `post_deleted`, аккуратное удаление MapController.
- У постов появился action удаления для владельца через `onDeleted`.

## Flutter: маршруты

- `StorageService` версия БД `2`.
- Добавлены `is_downloaded`, `source_post_id`, unique index по `source_post_id`.
- `saveRoute` возвращает inserted id.
- Убраны тяжелые full-table logs/backup из горячего пути.
- `loadRoutes` сортирует по дате и имеет лимит.

## Flutter: инфраструктура

- Добавлен единый `osmTileLayer()`.
- Добавлен `ApiErrorUi` / обработка API ошибок в части экранов.
- Push service сделан optional и не должен падать без Firebase dart-defines.

## Проверки

- `flutter analyze` зеленый.
- `flutter test` зеленый.
- `python -m compileall app` зеленый.
- `python -m pytest` зеленый: 27 passed.
