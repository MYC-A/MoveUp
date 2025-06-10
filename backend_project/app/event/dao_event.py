from typing import Any, List

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from .models_event import Event, EventParticipant, ApprovedType
from app.dao.base import BaseDAO


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
            **filter_by: Any
    ) -> List[Event]:
        # Маппинг полей для сортировки
        sort_column = {
            "id": Event.id,
            "start_time": Event.start_time,
            "title": Event.title,
        }.get(sort_by, Event.id)

        order_clause = sort_column.desc() if sort_order.lower() == "desc" else sort_column.asc()

        query = (
            select(Event)
            .filter_by(**filter_by)
            .order_by(order_clause)
            .offset(skip)
            .limit(limit)
        )
        result = await session.execute(query)
        return result.scalars().all()
    @classmethod
    async def find_one_or_none_by_id(cls, event_id: int, session: AsyncSession):
        query = select(cls.model).where(cls.model.id == event_id)
        result = await session.execute(query)
        return result.scalar_one_or_none()

    @classmethod
    async def create_event(
            cls,
            event_data: dict,
            organizer_id: int,
            session: AsyncSession
    ):
        if "max_participants" in event_data:
            event_data["available_seats"] = event_data["max_participants"]

        event = Event(**event_data, organizer_id=organizer_id)
        session.add(event)
        await session.commit()
        await session.refresh(event)
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
    ) -> EventParticipant:
        """
        Обновляет статус участника мероприятия.

        :param participant_id: ID участника мероприятия.
        :param event_id: ID мероприятия.
        :param new_status: Новый статус заявки (APPROVED, AWAITS, DENIED).
        :param session: Асинхронная сессия SQLAlchemy.
        :return: Обновленный участник мероприятия.
        :raises ValueError: Если участник не найден или нет доступных мест.
        :raises Exception: Если произошла ошибка при работе с базой данных.
        """
        try:
            # Находим участника по ID и проверяем, что он принадлежит указанному мероприятию
            participant = await session.execute(
                select(EventParticipant)
                .where(EventParticipant.id == participant_id)
                .where(EventParticipant.event_id == event_id)
            )
            participant = participant.scalar()
            if not participant:
                raise ValueError("Участник мероприятия не найден")

            # Получаем мероприятие по event_id
            event = await session.get(Event, event_id)
            if not event:
                raise ValueError("Мероприятие не найдено")

            # Текущий статус участника
            current_status = participant.approved

            # Если новый статус — APPROVED
            if new_status == ApprovedType.APPROVED:
                if event.available_seats <= 0:
                    raise ValueError("Нет доступных мест для участия")
                event.available_seats -= 1  # Уменьшаем количество доступных мест

            # Если текущий статус — APPROVED, а новый — не APPROVED
            elif current_status == ApprovedType.APPROVED and new_status != ApprovedType.APPROVED:
                event.available_seats += 1  # Увеличиваем количество доступных мест

            # Обновляем статус участника
            participant.approved = new_status
            await session.commit()
            return participant
        except Exception as e:
            await session.rollback()
            raise e

    @staticmethod
    async def get_participants_count(event_id: int, session: AsyncSession) -> int:
        result = await session.execute(
            select(func.count()).select_from(EventParticipant).where(
                EventParticipant.event_id == event_id,
                EventParticipant.approved == ApprovedType.APPROVED
            )
        )
        return result.scalar()
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