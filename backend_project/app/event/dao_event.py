from datetime import datetime
from typing import Any, List, Optional

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from .models_event import Event, EventParticipant, ApprovedType
from app.dao.base import BaseDAO
from app.users.models_user import User


class EventDAO(BaseDAO):
    model = Event

    @classmethod
    async def find_all(
            cls,
            session: AsyncSession,
            skip: int = 0,
            limit: int = 10,
            sort_by: str = "id",
            sort_order: str = "desc",
            q: Optional[str] = None,
            city: Optional[str] = None,
            available_only: bool = False,
            active_only: bool = True,
            **filter_by: Any
    ) -> List[Event]:
        # Маппинг полей для сортировки
        sort_column = {
            "id": Event.id,
            "start_time": Event.start_time,
            "title": Event.title,
        }.get(sort_by, Event.id)

        order_clause = sort_column.desc() if sort_order.lower() == "desc" else sort_column.asc()

        query = select(Event).options(
            selectinload(Event.organizer),
            selectinload(Event.participants),
        ).filter_by(**filter_by)

        if active_only:
            now = datetime.utcnow()
            query = query.where(
                or_(
                    Event.end_time >= now,
                    (Event.end_time.is_(None) & Event.start_time.is_(None)),
                    (Event.end_time.is_(None) & (Event.start_time >= now)),
                )
            )

        if city:
            query = query.where(Event.city == city)

        if available_only:
            query = query.where(Event.available_seats > 0)

        if q:
            search = f"%{q.strip()}%"
            query = query.outerjoin(User, Event.organizer_id == User.id).where(
                or_(
                    Event.title.ilike(search),
                    Event.description.ilike(search),
                    Event.goal.ilike(search),
                    Event.city.ilike(search),
                    User.full_name.ilike(search),
                    User.username.ilike(search),
                )
            )

        query = query.order_by(order_clause).offset(skip).limit(limit)
        result = await session.execute(query)
        return result.scalars().all()

    @classmethod
    async def find_one_or_none_by_id(cls, event_id: int, session: AsyncSession):
        query = (
            select(cls.model)
            .options(
                selectinload(Event.organizer),
                selectinload(Event.participants).selectinload(EventParticipant.user),
            )
            .where(cls.model.id == event_id)
        )
        result = await session.execute(query)
        return result.scalar_one_or_none()

    @classmethod
    async def create_event(
            cls,
            event_data: dict,
            organizer_id: int,
            session: AsyncSession,
            commit: bool = True,
    ):
        if "max_participants" in event_data:
            event_data["available_seats"] = event_data["max_participants"]

        event = Event(**event_data, organizer_id=organizer_id)
        session.add(event)
        if commit:
            await session.commit()
            await session.refresh(event)
        else:
            await session.flush()
        return event

    @classmethod
    async def create_event_with_route(
            cls,
            event_data: dict,
            route_points: list,
            organizer_id: int,
            session: AsyncSession
    ):
        """
        Создает мероприятие с маршрутом в JSON-формате
        """
        # Подготовка данных маршрута
        route_data = [{
            "latitude": point.latitude,
            "longitude": point.longitude,
            "timestamp": point.timestamp.isoformat() if point.timestamp else None
        } for point in route_points]

        # Установка доступных мест
        if "max_participants" in event_data:
            event_data["available_seats"] = event_data["max_participants"]

        # Создание события
        event = Event(
            **event_data,
            organizer_id=organizer_id,
            route_data=route_data
        )
        session.add(event)
        await session.commit()
        await session.refresh(event)
        return event


class EventParticipantDAO(BaseDAO):
    model = EventParticipant

    @classmethod
    async def add_participant(cls, event_id: int, user_id: int, session: AsyncSession):
        """
        Добавляет участника мероприятия.

        :param event_id: ID мероприятия.
        :param user_id: ID пользователя.
        :param session: Асинхронная сессия SQLAlchemy.
        :return: Участник мероприятия.
        :raises ValueError: Если пользователь уже является участником мероприятия.
        :raises Exception: Если произошла ошибка при работе с базой данных.
        """
        try:
            existing_participant = await session.execute(
                select(EventParticipant).where(
                    EventParticipant.event_id == event_id,
                    EventParticipant.user_id == user_id
                )
            )
            if existing_participant.scalar():
                raise ValueError("Пользователь уже является участником мероприятия")

            participant = EventParticipant(
                event_id=event_id,
                user_id=user_id,
                approved=ApprovedType.AWAITS
            )
            session.add(participant)
            await session.commit()
            return participant
        except Exception as e:
            await session.rollback()
            raise e

    @classmethod
    async def update_participant(
            cls,
            participant_id: int,
            event_id: int,  # Добавляем event_id для прямого доступа к мероприятию
            new_status: ApprovedType,
            session: AsyncSession,
            commit: bool = True,
    ) -> EventParticipant:
        """
        Обновляет статус участника мероприятия.

        :param participant_id: ID участника мероприятия.
        :param event_id: ID мероприятия.
        :param new_status: Новый статус заявки (APPROVED, AWAITS, DENIED).
        :param session: Асинхронная сессия SQLAlchemy.
        :param commit: Фиксировать изменения внутри DAO или оставить транзакцию вызывающему коду.
        :return: Обновленный участник мероприятия.
        :raises ValueError: Если участник не найден или нет доступных мест.
        :raises Exception: Если произошла ошибка при работе с базой данных.
        """
        try:
            event_result = await session.execute(
                select(Event)
                .where(Event.id == event_id)
                .with_for_update()
            )
            event = event_result.scalar_one_or_none()
            if not event:
                raise ValueError("Мероприятие не найдено")

            # Блокируем заявку в той же транзакции: два параллельных одобрения
            # не смогут одновременно списать одно и то же свободное место.
            participant_result = await session.execute(
                select(EventParticipant)
                .where(EventParticipant.id == participant_id)
                .where(EventParticipant.event_id == event_id)
                .with_for_update()
            )
            participant = participant_result.scalar_one_or_none()
            if not participant:
                raise ValueError("Участник мероприятия не найден")

            current_status = participant.approved

            approved_count_result = await session.execute(
                select(func.count()).select_from(EventParticipant).where(
                    EventParticipant.event_id == event_id,
                    EventParticipant.approved == ApprovedType.APPROVED,
                )
            )
            approved_count = approved_count_result.scalar() or 0

            if current_status == new_status:
                event.available_seats = max(
                    event.max_participants - approved_count,
                    0,
                )
                if commit:
                    await session.commit()
                return participant

            if (
                new_status == ApprovedType.APPROVED
                and current_status != ApprovedType.APPROVED
            ):
                if approved_count >= event.max_participants:
                    raise ValueError("Нет доступных мест для участия")

            participant.approved = new_status
            participant.status_changed = True
            await session.flush()

            approved_count_result = await session.execute(
                select(func.count()).select_from(EventParticipant).where(
                    EventParticipant.event_id == event_id,
                    EventParticipant.approved == ApprovedType.APPROVED,
                )
            )
            approved_count = approved_count_result.scalar() or 0
            event.available_seats = max(
                event.max_participants - approved_count,
                0,
            )

            if commit:
                await session.commit()
                await session.refresh(participant)
            else:
                await session.flush()
            return participant
        except Exception as e:
            if commit:
                await session.rollback()
            raise e

    @classmethod
    async def remove_participant(
            cls,
            participant_id: int,
            event_id: int,
            session: AsyncSession,
            commit: bool = True,
    ) -> EventParticipant:
        try:
            event_result = await session.execute(
                select(Event)
                .where(Event.id == event_id)
                .with_for_update()
            )
            event = event_result.scalar_one_or_none()
            if not event:
                raise ValueError("Мероприятие не найдено")

            result = await session.execute(
                select(EventParticipant)
                .where(EventParticipant.id == participant_id)
                .where(EventParticipant.event_id == event_id)
                .with_for_update()
            )
            participant = result.scalar_one_or_none()
            if not participant:
                raise ValueError("Участник мероприятия не найден")

            await session.delete(participant)
            await session.flush()

            approved_count_result = await session.execute(
                select(func.count()).select_from(EventParticipant).where(
                    EventParticipant.event_id == event_id,
                    EventParticipant.approved == ApprovedType.APPROVED,
                )
            )
            approved_count = approved_count_result.scalar() or 0
            event.available_seats = max(
                event.max_participants - approved_count,
                0,
            )

            if commit:
                await session.commit()
            else:
                await session.flush()
            return participant
        except Exception as e:
            if commit:
                await session.rollback()
            raise e

    @staticmethod
    async def get_pending_counts(event_ids: list[int], session: AsyncSession) -> dict[int, int]:
        if not event_ids:
            return {}

        result = await session.execute(
            select(EventParticipant.event_id, func.count())
            .where(
                EventParticipant.event_id.in_(event_ids),
                EventParticipant.approved == ApprovedType.AWAITS,
            )
            .group_by(EventParticipant.event_id)
        )
        return {event_id: count for event_id, count in result.all()}

    @staticmethod
    async def get_approved_counts(
        event_ids: list[int],
        session: AsyncSession,
    ) -> dict[int, int]:
        if not event_ids:
            return {}

        result = await session.execute(
            select(EventParticipant.event_id, func.count())
            .where(
                EventParticipant.event_id.in_(event_ids),
                EventParticipant.approved == ApprovedType.APPROVED,
            )
            .group_by(EventParticipant.event_id)
        )
        return {event_id: count for event_id, count in result.all()}

    @staticmethod
    async def get_participants_count(event_id: int, session: AsyncSession) -> int:
        result = await session.execute(
            select(func.count()).select_from(EventParticipant).where(
                EventParticipant.event_id == event_id,
                EventParticipant.approved == ApprovedType.APPROVED
            )
        )
        return result.scalar()

    @classmethod
    async def get_user_statuses(cls, user_id: int, event_ids: list[int], session: AsyncSession) -> dict[int, str]:
        """Возвращает {event_id: статус} участия пользователя для списка событий."""
        if not event_ids:
            return {}
        result = await session.execute(
            select(EventParticipant.event_id, EventParticipant.approved).where(
                EventParticipant.user_id == user_id,
                EventParticipant.event_id.in_(event_ids),
            )
        )
        return {row.event_id: row.approved.value for row in result.all()}

    @classmethod
    async def find_user_participant(cls, event_id: int, user_id: int, session: AsyncSession):
        result = await session.execute(
            select(EventParticipant).where(
                EventParticipant.event_id == event_id,
                EventParticipant.user_id == user_id,
            )
        )
        return result.scalar_one_or_none()
"""class RoutePointDAO(BaseDAO):
    model = RoutePoint

    @classmethod
    async def get_route_points_by_event_id(cls, event_id: int, session: AsyncSession):
        """"""
        Возвращает точки маршрута для мероприятия.

        :param event_id: ID мероприятия.
        :param session: Асинхронная сессия SQLAlchemy.
        :return: Список точек маршрута.
        """"""
        query = select(cls.model).filter(cls.model.event_id == event_id)
        result = await session.execute(query)
        return result.scalars().all()
"""
