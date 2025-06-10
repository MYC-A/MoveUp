from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from .schemas_event import EventCreate, EventRead, EventParticipantCreate
from .dao_event import EventDAO, EventParticipantDAO
from app.users.dependensies_user import get_current_user
from app.db.base import get_db
from typing import List
from fastapi import APIRouter, Request
from fastapi.templating import Jinja2Templates

from ..chat.models import GroupChat, group_chat_participants

templates = Jinja2Templates(directory="app/templates")
router = APIRouter(prefix="/events", tags=["Events"])

active_connections = {}

@router.get("/create_event")
async def create_event_page(request: Request):
    """Страница создания мероприятия."""
    return templates.TemplateResponse("create_event.html", {"request": request})

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

    # Создаем мероприятие
    event = await EventDAO.create_event(
        event_data=event_dict,
        organizer_id=current_user.id,
        session=db
    )

    # Если указан флаг создания группового чата
    if event_data.create_group_chat:
        # Создаем групповой чат
        group_chat = GroupChat(
            name=event_data.title,
            creator_id=current_user.id,
        )
        db.add(group_chat)
        await db.commit()
        await db.refresh(group_chat)

        # Добавляем организатора в группу
        stmt = group_chat_participants.insert().values(
            group_chat_id=group_chat.id,
            user_id=current_user.id
        )
        await db.execute(stmt)
        await db.commit()

        # Привязываем чат к мероприятию
        event.group_chat_id = group_chat.id
        await db.commit()

    # Обновляем объект события
    await db.refresh(event)

    # Преобразуем SQLAlchemy-модель в словарь
    event_dict = {
        "id": event.id,
        "title": event.title,
        "description": event.description,
        "event_type": event.event_type.value,
        "goal": event.goal,
        "start_time": event.start_time,
        "end_time": event.end_time,
        "difficulty": event.difficulty,
        "max_participants": event.max_participants,
        "is_public": event.is_public,
        "organizer_id": event.organizer_id,
        "available_seats": event.available_seats,
        "group_chat_id": event.group_chat_id,
        "route_data": event.route_data
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

@router.get("/", response_model=List[EventRead])
async def get_events(
    request: Request,
    skip: int = Query(0, ge=0, description="Количество пропускаемых записей"),
    limit: int = Query(5, ge=1, le=100, description="Лимит записей"),
    sort_by: str = Query("id", description="Поле для сортировки: id, start_time, title"),
    sort_order: str = Query("desc", description="Порядок сортировки: asc или desc"),
    db: AsyncSession = Depends(get_db),
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
        events = await EventDAO.find_all(
            session=db,
            skip=skip,
            limit=limit,
            sort_by=sort_by,
            sort_order=sort_order
        )

        events_read = [EventRead.model_validate(event) for event in events]
        events_dict = []
        for event in events_read:
            event_dict = event.dict()
            if event_dict.get("start_time"):
                event_dict["start_time"] = event_dict["start_time"].isoformat()
            if event_dict.get("end_time"):
                event_dict["end_time"] = event_dict["end_time"].isoformat()
            events_dict.append(event_dict)

        if format.lower() == "json":
            return events_dict

        return templates.TemplateResponse("events.html", {"request": request, "events": events_dict})

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ошибка загрузки мероприятий: {str(e)}")

@router.get("/{event_id}", response_model=EventRead)
async def get_event_details(
    event_id: int,
    db: AsyncSession = Depends(get_db)
):
    """Получение деталей мероприятия."""
    event = await EventDAO.find_one_or_none_by_id(event_id, session=db)
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")
    return EventRead.model_validate(event)

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

@router.post("/{event_id}/participate", response_model=EventParticipantCreate)
async def participate_event(
    event_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Запись пользователя на мероприятие."""
    participant = await EventParticipantDAO.add_participant(
        event_id=event_id,
        user_id=current_user.id,
        session=db
    )
    return participant

