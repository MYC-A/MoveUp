from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert

from app.db.base import async_session_maker
from app.push.models import PushToken


class PushTokenDAO:
    @classmethod
    async def upsert_token(
        cls,
        user_id: int,
        token: str,
        platform: str,
        device_id: str | None = None,
    ) -> None:
        async with async_session_maker() as session:
            stmt = (
                insert(PushToken)
                .values(
                    user_id=user_id,
                    token=token,
                    platform=platform,
                    device_id=device_id,
                    is_active=True,
                )
                .on_conflict_do_update(
                    index_elements=[PushToken.token],
                    set_={
                        "user_id": user_id,
                        "platform": platform,
                        "device_id": device_id,
                        "is_active": True,
                    },
                )
            )
            await session.execute(stmt)
            await session.commit()

    @classmethod
    async def deactivate_token(cls, token: str, user_id: int | None = None) -> None:
        async with async_session_maker() as session:
            stmt = update(PushToken).where(PushToken.token == token)
            if user_id is not None:
                stmt = stmt.where(PushToken.user_id == user_id)
            await session.execute(stmt.values(is_active=False))
            await session.commit()

    @classmethod
    async def deactivate_tokens(cls, tokens: list[str]) -> None:
        if not tokens:
            return

        async with async_session_maker() as session:
            stmt = update(PushToken).where(PushToken.token.in_(tokens))
            await session.execute(stmt.values(is_active=False))
            await session.commit()

    @classmethod
    async def get_active_tokens_for_user(cls, user_id: int) -> list[str]:
        async with async_session_maker() as session:
            query = select(PushToken.token).where(
                PushToken.user_id == user_id,
                PushToken.is_active == True,
            )
            result = await session.execute(query)
            return list(result.scalars().all())
