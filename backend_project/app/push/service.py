import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.core.config import settings
from app.push.dao import PushTokenDAO

logger = logging.getLogger(__name__)


def _short_token(token: str | None) -> str:
    if not token:
        return "<empty>"
    if len(token) <= 12:
        return token
    return f"{token[:6]}...{token[-6:]}"


try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:
    firebase_admin = None
    credentials = None
    messaging = None


class PushNotificationService:
    _initialized = False
    _init_failed = False

    @classmethod
    def _is_configured(cls) -> bool:
        return bool(settings.FCM_ENABLED and settings.FIREBASE_CREDENTIALS_PATH)

    @classmethod
    def is_enabled(cls) -> bool:
        return cls._is_configured()

    @classmethod
    def _initialize_firebase(cls) -> bool:
        if cls._initialized:
            return True
        if cls._init_failed:
            logger.warning("FCM initialization skipped: previous initialization failed")
            return False
        if not cls._is_configured():
            logger.warning(
                "FCM is disabled or not configured: FCM_ENABLED=%s, credentials_path_set=%s",
                settings.FCM_ENABLED,
                bool(settings.FIREBASE_CREDENTIALS_PATH),
            )
            return False
        if firebase_admin is None or credentials is None:
            logger.warning("FCM is enabled, but firebase-admin is not installed")
            cls._init_failed = True
            return False

        raw_path = settings.FIREBASE_CREDENTIALS_PATH

        # Частая ошибка: Windows-путь вида "C:\..." скопирован в .env на Linux.
        # На Linux такой путь трактуется как относительный (нет ведущего "/").
        import sys
        if sys.platform != "win32" and len(raw_path) >= 2 and raw_path[1] == ":":
            logger.error(
                "FIREBASE_CREDENTIALS_PATH выглядит как Windows-путь (%s). "
                "Загрузите service-account.json на VPS и укажите Linux-путь, "
                "например: FIREBASE_CREDENTIALS_PATH=./firebase-service-account.json",
                raw_path,
            )
            cls._init_failed = True
            return False

        credentials_path = Path(raw_path).expanduser()
        if not credentials_path.is_absolute():
            credentials_path = Path.cwd() / credentials_path

        if not credentials_path.exists():
            logger.warning(
                "Firebase credentials file not found: %s "
                "(resolved from '%s', cwd='%s')",
                credentials_path,
                raw_path,
                Path.cwd(),
            )
            cls._init_failed = True
            return False

        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(str(credentials_path))
                firebase_admin.initialize_app(cred)
            cls._initialized = True
            logger.info(
                "Firebase Admin SDK initialized: credentials=%s channel=%s",
                credentials_path,
                settings.FCM_ANDROID_CHANNEL_ID,
            )
            return True
        except Exception:
            logger.exception("Failed to initialize Firebase Admin SDK")
            cls._init_failed = True
            return False

    @classmethod
    async def send_chat_message_push(
        cls,
        recipient_id: int,
        title: str,
        body: str,
        data: dict[str, Any],
        unread_count: int,
    ) -> None:
        if not cls._initialize_firebase() or messaging is None:
            logger.warning(
                "FCM send skipped for user %s: firebase is not initialized",
                recipient_id,
            )
            return

        tokens = await PushTokenDAO.get_active_tokens_for_user(recipient_id)
        if not tokens:
            logger.warning("FCM send skipped for user %s: no active tokens", recipient_id)
            return

        logger.info(
            "FCM send start: user=%s tokens=%s type=%s conversation=%s:%s unread=%s",
            recipient_id,
            len(tokens),
            data.get("type"),
            data.get("conversation_type"),
            data.get("conversation_id") or data.get("group_chat_id"),
            unread_count,
        )

        invalid_tokens: list[str] = []
        sent_count = 0
        payload_data = {key: str(value) for key, value in data.items() if value is not None}
        payload_data["title"] = title
        payload_data["body"] = body
        payload_data["unread_count"] = str(unread_count)

        for token in tokens:
            message = messaging.Message(
                token=token,
                # Поле notification гарантирует, что ОС покажет уведомление
                # даже когда приложение убито (data-only этого не обеспечивает
                # на большинстве Android-производителей с агрессивной оптимизацией).
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=payload_data,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id=settings.FCM_ANDROID_CHANNEL_ID,
                        sound="default",
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default", badge=unread_count),
                    ),
                ),
            )

            try:
                message_id = await asyncio.to_thread(messaging.send, message)
                sent_count += 1
                logger.info(
                    "FCM send ok: user=%s token=%s message_id=%s",
                    recipient_id,
                    _short_token(token),
                    message_id,
                )
            except Exception as exc:
                if exc.__class__.__name__ in {
                    "UnregisteredError",
                    "SenderIdMismatchError",
                }:
                    logger.warning(
                        "FCM token invalid: user=%s token=%s error=%s",
                        recipient_id,
                        _short_token(token),
                        exc.__class__.__name__,
                    )
                    invalid_tokens.append(token)
                else:
                    logger.exception(
                        "Failed to send FCM message to user %s token=%s",
                        recipient_id,
                        _short_token(token),
                    )

        await PushTokenDAO.deactivate_tokens(invalid_tokens)
        logger.info(
            "FCM send done: user=%s sent=%s invalid=%s active_before=%s",
            recipient_id,
            sent_count,
            len(invalid_tokens),
            len(tokens),
        )


    @classmethod
    async def send_debug_push(cls, recipient_id: int) -> dict[str, Any]:
        """Sends an auth-only diagnostic push to the current user's devices."""
        result: dict[str, Any] = {
            "firebase_configured": cls._is_configured(),
            "firebase_initialized": False,
            "active_tokens": 0,
            "sent": 0,
            "invalid_tokens": 0,
            "errors": [],
        }

        if not cls._initialize_firebase() or messaging is None:
            logger.warning(
                "FCM debug push skipped for user %s: firebase is not initialized",
                recipient_id,
            )
            result["errors"].append("firebase_not_initialized")
            return result

        result["firebase_initialized"] = True
        tokens = await PushTokenDAO.get_active_tokens_for_user(recipient_id)
        result["active_tokens"] = len(tokens)
        if not tokens:
            logger.warning("FCM debug push skipped for user %s: no active tokens", recipient_id)
            result["errors"].append("no_active_tokens")
            return result

        invalid_tokens: list[str] = []
        now = datetime.now(timezone.utc).isoformat()
        logger.info("FCM debug push start: user=%s tokens=%s", recipient_id, len(tokens))

        for token in tokens:
            message = messaging.Message(
                token=token,
                notification=messaging.Notification(
                    title="MoveUp test push",
                    body=f"Diagnostic notification at {now}",
                ),
                data={
                    "type": "push_debug",
                    "title": "MoveUp test push",
                    "body": f"Diagnostic notification at {now}",
                    "debug_at": now,
                },
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id=settings.FCM_ANDROID_CHANNEL_ID,
                        sound="default",
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default", badge=1),
                    ),
                ),
            )

            try:
                message_id = await asyncio.to_thread(messaging.send, message)
                result["sent"] += 1
                logger.info(
                    "FCM debug push ok: user=%s token=%s message_id=%s",
                    recipient_id,
                    _short_token(token),
                    message_id,
                )
            except Exception as exc:
                if exc.__class__.__name__ in {
                    "UnregisteredError",
                    "SenderIdMismatchError",
                }:
                    invalid_tokens.append(token)
                    logger.warning(
                        "FCM debug token invalid: user=%s token=%s error=%s",
                        recipient_id,
                        _short_token(token),
                        exc.__class__.__name__,
                    )
                else:
                    error = f"{exc.__class__.__name__}: {exc}"
                    result["errors"].append(error)
                    logger.exception(
                        "FCM debug push failed: user=%s token=%s",
                        recipient_id,
                        _short_token(token),
                    )

        await PushTokenDAO.deactivate_tokens(invalid_tokens)
        result["invalid_tokens"] = len(invalid_tokens)
        logger.info(
            "FCM debug push done: user=%s sent=%s invalid=%s active_before=%s",
            recipient_id,
            result["sent"],
            result["invalid_tokens"],
            result["active_tokens"],
        )
        return result
