from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession
from .schemas_event import EventCreate, EventRead, EventParticipantCreate
from .dao_event import EventDAO, EventParticipantDAO
from .models_event import Event, EventParticipant, UserNotification
from .cities import EVENT_CITIES, canonical_city
from app.core.config import settings
from app.users.dependensies_user import get_current_user, get_current_user_optional
from app.db.base import get_db
from datetime import datetime
from typing import List, Optional
from fastapi.templating import Jinja2Templates

from ..chat.models import (
    GroupChat,
    GroupMessage,
    GroupMessageReadStatus,
    group_chat_participants,
)

templates = Jinja2Templates(directory="app/templates")
router = APIRouter(prefix="/events", tags=["Events"])

active_connections = {}

@router.get("/create_event")
async def create_event_page(request: Request):
    """Страница создания мероприятия."""
    return templates.TemplateResponse(
        "create_event.html",
        {
            "request": request,
            "open_route_api_key": settings.OPEN_ROUTE_API_KEY,
        },
    )

@router.post("/create", response_model=EventRead)
async def create_event(
    event_data: EventCreate,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Создание мероприятия с точками маршрута в JSON-формате."""
    event_dict = event_data.dict(exclude={"create_group_chat"})
    route_data = [point.dict() for point in event_data.route_data]
    event_dict["route_data"] = route_data
    # Сохраняем выбор организатора, чтобы чат можно было создать (в т.ч. лениво)
    # только если он действительно нужен.
    event_dict["group_chat_enabled"] = event_data.create_group_chat

    async with db.begin():
        event = await EventDAO.create_event(
            event_data=event_dict,
            organizer_id=current_user.id,
            session=db,
            commit=False,
        )

        if event_data.create_group_chat:
            group_chat = GroupChat(
                name=event_data.title,
                creator_id=current_user.id,
            )
            db.add(group_chat)
            await db.flush()

            await db.execute(
                group_chat_participants.insert().values(
                    group_chat_id=group_chat.id,
                    user_id=current_user.id,
                )
            )
            event.group_chat_id = group_chat.id

    await db.refresh(event)

    # Преобразуем SQLAlchemy-модель в словарь
    event_dict = {
        "id": event.id,
        "title": event.title,
        "description": event.description,
        "event_type": event.event_type.value,
        "goal": event.goal,
        "city": event.city,
        "start_time": event.start_time,
        "end_time": event.end_time,
        "difficulty": event.difficulty,
        "max_participants": event.max_participants,
        "is_public": event.is_public,
        "organizer_id": event.organizer_id,
        "available_seats": event.available_seats,
        "group_chat_id": event.group_chat_id,
        "route_data": event.route_data,
        "organizer_name": current_user.full_name or current_user.username,
        "participants_count": max(event.max_participants - event.available_seats, 0),
        "is_expired": False,
    }

    # Возвращаем данные через Pydantic-модель
    return EventRead(**event_dict)

@router.post("/{event_id}/participate", response_model=EventParticipantCreate)
async def participate_event(
    event_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Запись пользователя на мероприятие."""
    # Получаем мероприятие
    event = await EventDAO.find_one_or_none_by_id(event_id, session=db)
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")

    event_finish = event.end_time or event.start_time
    now = datetime.utcnow()
    if event_finish and event_finish.tzinfo is not None:
        now = datetime.now(event_finish.tzinfo)
    if event_finish and event_finish < now:
        raise HTTPException(
            status_code=400,
            detail="Мероприятие уже завершилось"
        )

    # Проверка на организатора
    if event.organizer_id == current_user.id:
        raise HTTPException(
            status_code=400,
            detail="Организатор не может записаться на свое мероприятие"
        )

    # Проверка свободных мест
    if event.available_seats <= 0:
        raise HTTPException(
            status_code=400,
            detail="Нет свободных мест для записи"
        )

    try:
        # Добавление участника
        participant = await EventParticipantDAO.add_participant(
            event_id=event_id,
            user_id=current_user.id,
            session=db
        )
        return EventParticipantCreate(
            event_id=participant.event_id,
            user_id=participant.user_id,
            approved=participant.approved
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail="Ошибка сервера: " + str(e)
        )


@router.delete("/{event_id}/participate")
async def cancel_participation(
    event_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Отмена записи на мероприятие (отписаться). Освобождает место, если
    заявка была одобрена."""
    try:
        participant = await EventParticipantDAO.find_user_participant(
            event_id, current_user.id, session=db
        )
        if not participant:
            raise HTTPException(
                status_code=404,
                detail="Вы не записаны на это мероприятие",
            )

        event_result = await db.execute(
            select(Event).where(Event.id == event_id).with_for_update()
        )
        event = event_result.scalar_one_or_none()
        if not event:
            raise HTTPException(status_code=404, detail="Мероприятие не найдено")

        removed_participant = await EventParticipantDAO.remove_participant(
            participant_id=participant.id,
            event_id=event_id,
            session=db,
            commit=False,
        )

        if event.group_chat_id is not None:
            await db.execute(
                delete(group_chat_participants).where(
                    (group_chat_participants.c.group_chat_id == event.group_chat_id)
                    & (group_chat_participants.c.user_id == removed_participant.user_id)
                )
            )

        await db.commit()
        return {"status": "ok", "msg": "Запись отменена"}
    except HTTPException:
        await db.rollback()
        raise
    except ValueError as e:
        await db.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Ошибка сервера: " + str(e))


@router.get("/", response_model=List[EventRead])
async def get_events(
    request: Request,
    skip: int = Query(0, ge=0, description="Количество пропускаемых записей"),
    limit: int = Query(5, ge=1, le=100, description="Лимит записей"),
    sort_by: str = Query("id", description="Поле для сортировки: id, start_time, title"),
    sort_order: str = Query("desc", description="Порядок сортировки: asc или desc"),
    q: Optional[str] = Query(None, description="Поиск по названию, описанию, городу или организатору"),
    city: Optional[str] = Query(None, description="Город из списка поддерживаемых городов"),
    available_only: bool = Query(False, description="Показывать только события со свободными местами"),
    active_only: bool = Query(True, description="Скрывать завершенные события"),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user_optional),
    format: str = Query("html", description="Формат ответа: html или json")
):
    """Получение списка мероприятий и отображение HTML-страницы или возврат JSON."""
    valid_sort_fields = {"id", "start_time", "title"}
    valid_formats = {"html", "json"}

    if sort_by not in valid_sort_fields:
        raise HTTPException(status_code=422, detail=f"Недопустимое значение sort_by. Разрешены: {valid_sort_fields}")
    if sort_order.lower() not in {"asc", "desc"}:
        raise HTTPException(status_code=422, detail="sort_order должен быть 'asc' или 'desc'")
    if format.lower() not in valid_formats:
        raise HTTPException(status_code=422, detail=f"Недопустимый формат. Разрешены: {valid_formats}")

    try:
        canonical = canonical_city(city) if city else None
        if city and canonical is None:
            raise HTTPException(status_code=422, detail="Выберите город из списка")

        events = await EventDAO.find_all(
            session=db,
            skip=skip,
            limit=limit,
            sort_by=sort_by,
            sort_order=sort_order,
            q=q,
            city=canonical,
            available_only=available_only,
            active_only=active_only,
        )

        events_read = [EventRead.model_validate(event) for event in events]

        event_ids = [e.id for e in events_read]
        approved_counts = await EventParticipantDAO.get_approved_counts(
            event_ids, session=db
        )

        # Статус участия текущего пользователя для всех событий страницы (1 запрос).
        status_map = {}
        pending_counts = {}
        if current_user is not None:
            status_map = await EventParticipantDAO.get_user_statuses(
                current_user.id, event_ids, session=db
            )
            own_event_ids = [
                event.id for event in events_read
                if event.organizer_id == current_user.id
            ]
            pending_counts = await EventParticipantDAO.get_pending_counts(
                own_event_ids, session=db
            )

        events_dict = []
        for event in events_read:
            event_dict = event.dict()
            approved_count = approved_counts.get(event.id, 0)
            event_dict["available_seats"] = max(
                event.max_participants - approved_count,
                0,
            )
            event_dict["participants_count"] = approved_count
            event_dict["my_status"] = status_map.get(event.id)
            event_dict["pending_applications_count"] = pending_counts.get(event.id, 0)
            if event_dict.get("start_time"):
                event_dict["start_time"] = event_dict["start_time"].isoformat()
            if event_dict.get("end_time"):
                event_dict["end_time"] = event_dict["end_time"].isoformat()
            events_dict.append(event_dict)

        if format.lower() == "json":
            return events_dict

        return templates.TemplateResponse("events.html", {"request": request, "events": events_dict})

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка загрузки мероприятий: {str(e)}")


@router.get("/cities", response_model=List[str])
async def get_event_cities():
    return list(EVENT_CITIES)


@router.get("/server_time")
async def get_server_time():
    """Текущее серверное время (UTC) — чтобы клиент валидировал даты не по
    возможно неверным часам телефона."""
    return {"now": datetime.utcnow().isoformat() + "Z"}

@router.get("/{event_id}", response_model=EventRead)
async def get_event_details(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user_optional),
):
    """Получение деталей мероприятия."""
    event = await EventDAO.find_one_or_none_by_id(event_id, session=db)
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")
    result = EventRead.model_validate(event)
    approved_counts = await EventParticipantDAO.get_approved_counts(
        [event_id], session=db
    )
    approved_count = approved_counts.get(event_id, 0)
    result.available_seats = max(
        result.max_participants - approved_count,
        0,
    )
    result.participants_count = approved_count
    if current_user is not None:
        participant = await EventParticipantDAO.find_user_participant(
            event_id, current_user.id, session=db
        )
        result.my_status = participant.approved.value if participant else None
    return result

@router.get("/{event_id}/route", response_model=List[dict])
async def get_event_route(
    event_id: int,
    db: AsyncSession = Depends(get_db)
):
    """Получение точек маршрута мероприятия."""
    event = await EventDAO.find_one_or_none_by_id(event_id, session=db)
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")
    return event.route_data or []


@router.delete("/{event_id}")
async def delete_event(
    event_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Удаление мероприятия его организатором: оповещает участников,
    чистит групповой чат и связанные записи."""
    result = await db.execute(
        select(Event).filter(Event.id == event_id)
    )
    event = result.scalars().first()
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")
    if event.organizer_id != current_user.id:
        raise HTTPException(
            status_code=403, detail="Только организатор может удалить мероприятие"
        )

    # Снимок данных до удаления.
    chat_id = event.group_chat_id
    event_title = event.title

    # Кому слать оповещение — все, кто был связан с событием (заявка в любом статусе).
    participant_ids_result = await db.execute(
        select(EventParticipant.user_id).where(EventParticipant.event_id == event_id)
    )
    participant_ids = {uid for (uid,) in participant_ids_result.all()}

    # Персистентные уведомления — переживут удаление события.
    for uid in participant_ids:
        db.add(UserNotification(
            user_id=uid,
            type="event_deleted",
            title=event_title,
            body="Мероприятие отменено организатором",
        ))

    # Точки маршрута лежат в JSON-поле event.route_data, отдельной таблицы нет.
    # Удаляем участников и само событие; flush снимает FK event.group_chat_id.
    await db.execute(delete(EventParticipant).where(EventParticipant.event_id == event_id))
    await db.delete(event)
    await db.flush()

    # Чистим групповой чат события, если он был (иначе остаётся «осиротевшим»).
    if chat_id is not None:
        await db.execute(
            delete(GroupMessageReadStatus).where(
                GroupMessageReadStatus.group_chat_id == chat_id
            )
        )
        await db.execute(
            delete(GroupMessage).where(GroupMessage.group_chat_id == chat_id)
        )
        await db.execute(
            group_chat_participants.delete().where(
                group_chat_participants.c.group_chat_id == chat_id
            )
        )
        await db.execute(delete(GroupChat).where(GroupChat.id == chat_id))

    await db.commit()
    return {"status": "ok", "deleted_event_id": event_id}
