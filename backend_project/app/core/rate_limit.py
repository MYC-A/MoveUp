import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request, status


class RateLimiter:
    """Простой in-memory лимитер по IP (на один процесс). Для одного инстанса
    достаточно; при горизонтальном масштабировании нужен общий стор (Redis).

    Используется как FastAPI-зависимость: Depends(RateLimiter(5, 60)).
    Каждый лимит должен быть отдельным module-level экземпляром, чтобы
    состояние сохранялось между запросами.
    """

    def __init__(self, max_calls: int, period_seconds: int):
        self.max_calls = max_calls
        self.period = period_seconds
        self._hits: dict[str, deque] = defaultdict(deque)

    async def __call__(self, request: Request) -> None:
        key = request.client.host if request.client else "unknown"
        now = time.monotonic()
        hits = self._hits[key]
        # Чистим устаревшие отметки.
        while hits and now - hits[0] > self.period:
            hits.popleft()
        if len(hits) >= self.max_calls:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Слишком много попыток. Попробуйте позже.",
            )
        hits.append(now)
        # Не даём словарю расти бесконечно: убираем пустые ключи изредка.
        if len(self._hits) > 10000:
            empty = [k for k, v in self._hits.items() if not v]
            for k in empty:
                self._hits.pop(k, None)


# Лимиты для чувствительных эндпоинтов (общие экземпляры — состояние shared).
login_rate_limiter = RateLimiter(max_calls=10, period_seconds=60)
register_rate_limiter = RateLimiter(max_calls=5, period_seconds=300)
verify_rate_limiter = RateLimiter(max_calls=10, period_seconds=300)
resend_rate_limiter = RateLimiter(max_calls=3, period_seconds=300)
