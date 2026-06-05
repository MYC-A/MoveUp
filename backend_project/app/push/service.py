import asyncio
import logging
from pathlib import Path
from typing import Any

from app.core.config import settings
from app.push.dao import PushTokenDAO

logger = logging.getLogger(__name__)

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
        if cls._init_failed or not cls._is_configured():
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
            return

        tokens = await PushTokenDAO.get_active_tokens_for_user(recipient_id)
        if not tokens:
            return

        invalid_tokens: list[str] = []
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
                await asyncio.to_thread(messaging.send, message)
            except Exception as exc:
                if exc.__class__.__name__ in {
                    "UnregisteredError",
                    "SenderIdMismatchError",
                }:
                    invalid_tokens.append(token)
                else:
                    logger.exception("Failed to send FCM message to user %s", recipient_id)

        await PushTokenDAO.deactivate_tokens(invalid_tokens)
