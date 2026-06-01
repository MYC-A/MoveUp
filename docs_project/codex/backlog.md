# Backlog и слабые места

Дата актуализации: 2026-06-01.

## Документация и процесс

1. В корневом README ранее упоминалась `docs/agent/`, но `.gitignore` игнорирует эту папку, а tracked заметки находятся в `docs_project/codex/`.
   - Текущий tracked источник памяти: `docs_project/codex/`.
   - Если нужна локальная ephemeral-память агента, можно использовать `docs/agent/`, но она не попадет в git.

2. Alembic scaffold есть, но реальных migration versions пока нет.
   - `backend_project/migrations/versions/.gitkeep` есть.
   - Для production-эволюции БД нужно завести baseline/первые миграции и договориться, когда использовать `create_all`, а когда Alembic.

## Высокий приоритет

1. Feed WebSocket event handling.
   - `_handleWebSocketUpdate` сейчас debounce-ит события одним timer и может потерять промежуточные события из короткой пачки.
   - Нужно либо обрабатывать события сразу точечно, либо копить очередь и применять все события.
   - Отдельно добавить обработку `comment_deleted`, потому что backend уже отправляет этот event.

2. Timezone для постов/чата.
   - `Post.fromJson` вручную вычитает 5 часов из `created_at`.
   - Personal chat WebSocket payload не содержит `created_at`, из-за чего входящие realtime-сообщения могут отображаться без времени.
   - Лучше привести backend к timezone-aware UTC DTO и на Flutter использовать `DateTime.parse(...).toLocal()`.

3. Debug/log cleanup.
   - Backend еще содержит много `print(...)` в chat/posts/profile routes.
   - Flutter еще содержит `print(...)` в нескольких UI/служебных местах.
   - Токены уже не выглядят как явно печатающиеся в auth service, но response body/status и пользовательские данные в логах стоит пройти отдельно.

4. CORS/security.
   - `ALLOWED_ORIGINS` по умолчанию `*`.
   - Для production с cookie auth лучше явные origins.

5. Тестовое покрытие.
   - Backend тесты появились и зеленые, но пока покрывают в основном схемы/security/uploads.
   - Нужны integration/API tests для заявок, уведомлений, постов, комментариев, чатов, удаления события/поста.
   - Flutter пока имеет smoke test логина; нужны widget tests для ленты, комментариев, profile/events flows.

## Производительность

1. Лента с маршрутами.
   - Уже сделано: `PostItem` вынесен в `widgets/feed/post_item.dart`, карта в `_PostRouteMap`, точки кешируются, маршрут прореживается до 150 preview points, `VisibilityDetector` зумит один раз, добавлен `RepaintBoundary`, используется `osmTileLayer()` с кешем тайлов.
   - Риск: `PostItem` все еще использует `AutomaticKeepAliveClientMixin` и `wantKeepAlive => true`; при большом количестве постов с картами это может держать тяжелые карты в памяти.
   - Следующий шаг при лагах: проверить память/scroll jank и решить, нужен ли keep-alive всему посту.

2. StorageService.
   - Стало лучше: убраны full-table dumps и backup на каждую запись, `loadRoutes` ограничен лимитом, ошибки чтения пробрасываются.
   - Осторожно: backup остается явным методом; не использовать в горячем пути.

3. Карты в других местах.
   - Есть единый `osmTileLayer()`, стоит проверять, что новые карты используют его вместо своих `TileLayer`.
   - `widgets/route_details/RouteMap.dart` стоит отдельно посмотреть на `Future.delayed` в конструкторе, если будут лаги/странный zoom.

## Логика и UX

1. Уведомления.
   - Вынесены в `routes_notifications.py`.
   - Добавлены `event_updates` через `UserNotification`, чтобы уведомления жили даже после удаления события.
   - Нужно покрыть API-тестами mark read / single read / deleted event updates.

2. Посты и комментарии.
   - Backend разрешает удалять комментарий автору комментария или владельцу поста.
   - Flutter bottom sheet сейчас показывает delete action только автору комментария; владельцу поста нужно передавать `post.userId` и разрешать удаление чужих комментариев в своем посте.
   - При удалении поста записи в БД чистятся, но MinIO-объекты фотографий могут оставаться orphan-файлами.

3. Чаты.
   - `active_connections: Dict[int, WebSocket]` держит только один socket на пользователя; второй девайс/вкладка перезапишет первый.
   - `send_message` лучше возвращать сохраненное сообщение с `id`, `created_at`, `is_read`, а не request schema.
   - Нужен единый payload shape для personal/group realtime messages.

4. Мои заявки и мероприятия.
   - Backend фильтрует активные события в `get_user_applications`.
   - Нужны тесты на timezone/naive datetime и pagination edge cases.

5. Скачанные маршруты.
   - `source_post_id` и unique index есть.
   - Старые дубли, созданные до миграции, автоматически не чистятся.

6. Push-уведомления.
   - FCM сделан optional через env/dart-defines.
   - Нужна ручная проверка на реальном Android/device с Firebase config.
