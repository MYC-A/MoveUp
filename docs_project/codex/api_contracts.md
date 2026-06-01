# API Contracts And Gaps

Дата актуализации: 2026-06-01.

## Auth

Backend: `backend_project/app/users/router_users.py` (`prefix=/auth`).
Flutter: `flutter_project/lib/services_api/auth_service.dart`.

| Backend endpoint | Flutter method | Notes |
| --- | --- | --- |
| `POST /auth/register/` | `AuthService.register` | Creates unverified user and verification code. |
| `POST /auth/verify_email/` | `AuthService.verifyEmail` | Verifies code, returns access/refresh, sets access cookie. |
| `POST /auth/resend_code/` | `AuthService.resendCode` | Regenerates verification code. |
| `POST /auth/login/` | `AuthService.login` | Returns access/refresh; 403 `EMAIL_NOT_VERIFIED` is special-cased by client. |
| `POST /auth/refresh/` | `AuthService.tryRefreshTokens` | Stateless refresh-token rotation; returns new pair. |
| `POST /auth/change_password/` | `AuthService.changePassword` | Requires access cookie. |
| `POST /auth/logout/` | `AuthService.logout` | Deletes access cookie on backend. |
| `GET /auth/current_user` | several services | Returns integer user id. |

Gaps/risks:

1. Flutter `logout()` deletes `access_token` and `user_id`, but does not delete `refresh_token`. Since `getCurrentUserId()` requires access token this may not auto-login immediately, but stale refresh remains in secure storage.
2. Refresh tokens are stateless; logout cannot invalidate an already issued refresh token server-side.
3. Backend still uses `datetime.utcnow()` in email verification fields; token creation itself uses timezone-aware UTC.

## Profile, notifications, follows

Backend:

- `app/lk/routes_profile.py` (`prefix=/profile`).
- `app/lk/routes_notifications.py` (`prefix=/profile`, effective URLs start with `/profile/profile/notifications`).
- `app/friendship/routes_friends.py` (`prefix=/friends`).

Flutter:

- `LkService` for own profile/events/applications/notifications.
- `LkUsersService` for other profiles/follow graph.

Important endpoints:

| Backend endpoint | Flutter method/screen | Notes |
| --- | --- | --- |
| `GET /profile/?format=json` | `LkService.fetchProfile` | Own profile + stats. Caches `user_weight` for route calories. |
| `PUT /profile/` | `LkService.updateProfile` | Multipart profile update, optional avatar. |
| `GET /profile/events` | `LkService.fetchEvents` | Own organized events. |
| `GET /profile/user/applications` | `LkService.fetchUserApplications` | Own applications; backend filters active events. |
| `GET /profile/event/{id}/applications` | `LkService.fetchEventApplications` | Organizer-only pending applications. |
| `POST /profile/event/{id}/applications/{participant_id}/approve` | `LkService.approveApplication` | Can lazily create event group chat if enabled. |
| `POST /profile/event/{id}/applications/{participant_id}/reject` | `LkService.rejectApplication` | Rejects pending/participant application. |
| `GET /profile/event/{id}/participants` | `LkService.fetchEventParticipants` | Organizer-only approved participants. |
| `DELETE /profile/event/{id}/participants/{participant_id}` | `LkService.removeEventParticipant` | Removes approved participant and chat membership. |
| `GET /profile/profile/notifications` | `LkService.fetchNotifications` | Double `profile/profile` is intentional current contract. |
| `POST /friends/follow/{user_id}` | `LkUsersService.followUser` | Follow user. |
| `DELETE /friends/unfollow/{user_id}` | `LkUsersService.unfollowUser` | Unfollow user. |

Gaps/risks:

1. `LkService.fetchProfile()` still prints full response body. This can expose profile data in logs.
2. Notification URLs are odd (`/profile/profile/...`) because of router prefix + route path. Client matches it, but future refactors can easily break it.
3. Active-event filtering uses naive `datetime.utcnow()` and DB datetime fields. Timezone consistency should be fixed before relying on edge cases around current time.

## Posts, feed, comments

Backend: `backend_project/app/posts/routes_posts.py` (`prefix=/post`).
Flutter:

- `PostService`.
- `FeedScreen`.
- `UserPosts`.
- `PostItem`.
- `post_comments_sheet.dart`.
- Legacy `PostDetails_screen.dart`.

Important endpoints:

| Backend endpoint | Flutter method/screen | Notes |
| --- | --- | --- |
| `GET /post/feed` | `PostService.getFeed` | Feed DTO includes user, counters, liked state, photo URLs. |
| `POST /post/posts_create` | `PostService.createPost` | Multipart field `post` + optional `photos`. |
| `POST /post/posts/{id}/like` | `PostService.likePost` | Broadcasts `type=like`. |
| `POST /post/posts/{id}/create_comment` | `PostService.addComment` | Broadcasts `type=comment` with `comments_count` and comment DTO. |
| `DELETE /post/posts/{id}/comments/{comment_id}` | `PostService.deleteComment` | Broadcasts `type=comment_deleted`. |
| `DELETE /post/posts/{id}` | `PostService.deletePost` | Broadcasts `type=post_deleted`. |
| `GET /post/posts/{id}/comments` | `PostService.getComments` | Paginated comments. |
| `GET /post/posts/{id}/details` | `PostService.getPostDetails` | Used by legacy PostDetailsScreen. |
| `WS /post/ws/feed` | `WebSocketService.connectToFeed` | Feed realtime. No auth token on this socket. |
| `WS /post/ws/post/{id}` | `WebSocketService.connectToPost` | Post details realtime. No auth token on this socket. |

Current behavior:

- Main feed route preview is optimized in `widgets/feed/post_item.dart`: cached route points, 150 preview points, `VisibilityDetector`, `RepaintBoundary`, shared `osmTileLayer()`.
- Chat-list avatar issue is not in feed, but feed post avatar also uses the post `user.avatar_url` and normalizes local MinIO URLs.
- Comments are now primarily a bottom sheet, not a full post details page.

Gaps/risks:

1. `FeedScreen._handleWebSocketUpdate` uses one debounce timer; rapid event bursts can drop intermediate updates.
2. `FeedScreen` does not handle `comment_deleted`, even though backend broadcasts it.
3. `UserPosts` repeats the same debounce pattern and also does not handle `comment_deleted`.
4. `PostItem` keeps the whole card alive with `AutomaticKeepAliveClientMixin`; many route maps can increase memory pressure.
5. `Post.fromJson` manually subtracts 5 hours from `created_at`. Backend returns naive `datetime.utcnow().isoformat()`, so this is a timezone bug waiting to surface.
6. Backend delete post removes DB rows, but MinIO post photo objects are not visibly deleted.
7. Bottom sheet delete UI only allows comment author delete; backend also allows post owner delete.
8. `PostDetailsScreen` is legacy and duplicates old logic:
   - old route download code does `DateTime.parse(point['timestamp'])` and can fail if timestamp is missing;
   - it does not use shared `saveRouteFromPost()`;
   - it does not handle `comment_deleted`;
   - it recomputes route `LatLng` in build and uses delayed map zoom.
9. Feed/post WebSockets currently do not authenticate users. It is okay for public broadcast if intended, but this should be an explicit decision.

## Events and applications

Backend: `backend_project/app/event/routers_event.py`, schemas in `schemas_event.py`, DAO in `dao_event.py`.
Flutter: `EventService`, `EventScreen`, `CreateEventScreen`, profile applications screens.

Important endpoints:

| Backend endpoint | Flutter method/screen | Notes |
| --- | --- | --- |
| `GET /events/` | `EventService.getEvents` | Supports q/city/sort/available_only/active_only; returns `my_status` if authenticated. |
| `GET /events/cities` | `EventService.getEventCities` | Client falls back to built-in cities. |
| `GET /events/server_time` | `EventService.getServerTime` | Client uses this when validating create-event time. |
| `POST /events/create` | `EventService.createEvent` | Route JSON in event body; optional group chat flag. |
| `POST /events/{id}/participate` | `EventService.participateEvent` | Creates `AWAITS` application; organizer cannot apply. |
| `DELETE /events/{id}/participate` | `EventService.cancelParticipation` | Removes participant/application and frees seat if approved. |
| `GET /events/{id}` | `LkService.fetchEventDetails` / event screens | Event detail. |
| `GET /events/{id}/route` | not clearly used by Flutter | Route data endpoint. |
| `DELETE /events/{id}` | `EventService.deleteEvent` | Organizer delete; creates persistent notifications and cleans group chat. |

Current behavior:

- Backend validates route point bounds, route length <= 200 km, max participants >= 1, and end time > start time.
- Client also prevents route length > 200 km and moves map to selected city from a hard-coded city center map.
- Client has a “Стереть” route button in create event once route points exist.
- Backend filters active events in event list and in own applications.
- Group chat can be created immediately or lazily on first approval depending on `create_group_chat`/`group_chat_enabled`.

Gaps/risks:

1. Backend does not prevent creating events in the past. The client checks server time, but direct API calls can bypass it.
2. Timezone handling is mixed: backend and DB use naive datetimes in several places, client sends local ISO strings, and filters use `datetime.utcnow()`.
3. `CreateEventScreen` still has older visual style compared to newer app theme (`Card` stacks, green/blue gradient, direct `Colors.*`).
4. City map centering is hard-coded in Flutter. If backend city list changes, map centers can silently miss new cities.
5. Pending applications are not limited by `available_seats`; seat availability is enforced on approval. This may be acceptable, but UX can show many pending applicants for few seats.
6. No integration tests cover create/participate/approve/reject/delete event flows.

## Chat and push

Backend:

- `app/chat/router.py`, `dao.py`, `models.py`, `schemas.py`.
- `app/push/router.py`, `dao.py`, `service.py`.

Flutter:

- `ChatService`.
- `ChatListScreen`.
- `ChatScreen`.
- `GroupChatScreen`.
- `PushNotificationService`.

Important chat endpoints:

| Backend endpoint | Flutter method/screen | Notes |
| --- | --- | --- |
| `GET /chat/?format=json` | `ChatService.getChatData` | Current user, users with messages, group chats. |
| `GET /chat/unread_messages_count` | `ChatService.getUnreadMessagesCount` | Personal + group unread maps. |
| `POST /chat/mark_as_read` | `ChatService.markMessagesAsRead` | Marks personal messages from recipient as read. |
| `GET /chat/messages/{user_id}` | `ChatService.getMessagesBetweenUsers` | Paged by `limit` and `before_id`. |
| `POST /chat/messages` | `ChatService.sendMessage` | Personal send. |
| `POST /chat/group_chats/messages` | `ChatService.sendGroupMessage` | Group send, participant-checked. |
| `GET /chat/group_chats/{id}/get_messages` | `ChatService.getGroupMessages` | Group paginated messages. |
| `POST /chat/group_chats/{id}/mark_as_read` | `ChatService.markGroupMessagesAsRead` | Group mark read. |
| `POST /chat/group_chats` | `ChatService.createGroupChat` | Creates group chat. |
| `POST /chat/group_chats/{id}/add_participant` | `ChatService.addParticipantToGroupChat` | Adds one participant. |
| `POST /chat/group_chats/{id}/leave` | `ChatService.leaveGroupChat` | Leave group. |
| `GET /chat/group_chats/{id}/participants` | `ChatService.getGroupChatParticipants` | Participants with names/avatars. |
| `WS /chat/ws/{user_id}?token=...` | `ChatService.connectToChat` | JWT-checked WebSocket. |

Push endpoints:

| Backend endpoint | Flutter method | Notes |
| --- | --- | --- |
| `POST /push/tokens` | `PushNotificationService._registerTokenOnBackend` | Register/upsert FCM token. |
| `POST /push/tokens/delete` | `PushNotificationService.unregisterCurrentDeviceToken` | Deactivate token on logout. |

Current behavior:

- Chat WebSocket authenticates via query token and checks token subject matches path `user_id`.
- Chat list now shows personal avatars with `CachedNetworkImage` and `AppConfig.normalizeMediaUrl()`.
- Group participants sheet shows participant avatars.
- Push is optional: if Firebase dart-defines are missing, app keeps running.
- Push notification tap opens personal or group chat through the global navigator key.

Gaps/risks:

1. Backend `active_connections: Dict[int, WebSocket]` supports only one active socket per user. A second device/tab overwrites the first.
2. Personal `Message` model and `MessageRead` schema do not include `created_at`, while Flutter chat UI can display time if present.
3. Personal send response is `MessageCreate` request data, not the saved message DTO. Client currently ignores it and creates local optimistic message without id.
4. Personal realtime payload lacks `created_at`; incoming realtime messages can display without time until reload.
5. `GroupChatScreen._formatDateTime()` adds 5 hours manually to parsed backend time; this repeats the broader timezone problem.
6. `PushTokenDAO` and group message read insertion use PostgreSQL `insert(...).on_conflict...`; despite some SQLite compatibility code elsewhere, these paths are PostgreSQL-specific.
7. No tests cover WebSocket auth mismatch, payload shapes, unread counts, push token upsert, or multi-device socket behavior.

## Local routes/storage

Flutter:

- `StorageService`.
- `RouteHistoryScreen`.
- `RouteDetailsScreen`.
- `RouteViewScreen`.
- `post_route_downloader.dart`.

Current behavior:

- Local route DB version is `2`.
- `routes.source_post_id` has a unique index, so downloading the same post route replaces existing downloaded copy instead of creating endless duplicates.
- `RouteDetailsScreen` hides photo editing and publishing for downloaded routes.
- Downloaded route still allows changing name/description and has a hint that it is for repeat runs.
- Route preview in details shows start/finish markers.

Gaps/risks:

1. Old duplicates created before `source_post_id` migration are not automatically cleaned.
2. `source_post_id` is stored in SQLite but not represented on `RunningRoute` after load; current dedupe still works for new downloads because insert uses post id as source id.
3. `RouteDetailsScreen._zoomToRoute()` still uses `Future.delayed`; if route map glitches remain, convert to a stateful map preview pattern like feed maps.
4. `RunningRoute` and `StorageService` still produce many debug logs in route hot paths.
