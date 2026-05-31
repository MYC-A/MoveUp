import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger(__name__)


class EmailService:
    """Отправка писем через SMTP. Если почта не настроена (EMAIL_ENABLED=false
    или пустой SMTP_HOST) — письмо не уходит, а код пишется в лог, чтобы фича
    работала в dev без почтового сервера."""

    @staticmethod
    def is_enabled() -> bool:
        return bool(settings.EMAIL_ENABLED and settings.SMTP_HOST)

    @classmethod
    async def send_verification_code(cls, to_email: str, code: str) -> None:
        subject = "Подтверждение регистрации в MoveUp"
        body = (
            f"Ваш код подтверждения: {code}\n\n"
            "Введите его в приложении, чтобы завершить регистрацию.\n"
            "Код действует 30 минут."
        )
        if not cls.is_enabled():
            logger.warning(
                "EMAIL отключён — код подтверждения для %s: %s", to_email, code
            )
            return
        # SMTP синхронный — выносим в поток, чтобы не блокировать event loop.
        await asyncio.to_thread(cls._send_sync, to_email, subject, body)

    @classmethod
    def _send_sync(cls, to_email: str, subject: str, body: str) -> None:
        message = EmailMessage()
        message["From"] = settings.SMTP_FROM
        message["To"] = to_email
        message["Subject"] = subject
        message.set_content(body)

        try:
            with smtplib.SMTP(
                settings.SMTP_HOST, settings.SMTP_PORT, timeout=15
            ) as server:
                if settings.SMTP_USE_TLS:
                    server.starttls()
                if settings.SMTP_USERNAME:
                    server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
                server.send_message(message)
        except Exception as exc:  # noqa: BLE001 — письмо не критично для регистрации
            logger.error("Не удалось отправить письмо на %s: %s", to_email, exc)
