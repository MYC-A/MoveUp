"""Уведомления пользователя (заявки/изменения/системные). Вынесены из
routes_profile, чтобы не смешивать с профилем. Префикс тот же — /profile,
поэтому URL для клиента не меняются."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, update
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import get_db
from app.event.models_event import Event, EventParticipant, ApprovedType, UserNotification
from app.users.dependensies_user import get_current_user_id

router = APIRouter(prefix="/profile", tags=["Notifications"])


@router.get("/profile/notifications", response_model=dict)
async def get_user_notifications(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Получаем мероприятия, которые организовал текущий пользователь
    organized_events_result = await db.execute(
        select(Event.id, Event.title)  # Выбираем ID и название мероприятий
        .filter(Event.organizer_id == current_user)
    )
    organized_events = organized_events_result.all()  # Получаем список кортежей (id, title)
    organized_event_titles = {event_id: title for event_id, title in organized_events}
    organized_event_ids = list(organized_event_titles.keys())

    # Получаем новые заявки на мероприятия, которые организовал пользователь
    if organized_event_ids:
        new_applications_result = await db.execute(
            select(EventParticipant.event_id, func.count())
            .filter(
                EventParticipant.event_id.in_(organized_event_ids),
                EventParticipant.approved == ApprovedType.AWAITS,
                EventParticipant.is_new == True  # Только новые заявки
            )
            .group_by(EventParticipant.event_id)
        )
        new_applications = new_applications_result.all()  # Список кортежей (event_id, count)
    else:
        new_applications = []

    # Получаем изменения в статусе заявок, которые подал пользователь
    # (одобрение/отклонение). INVITED сюда не входит — это отдельный раздел
    # приглашений со своими действиями (принять/отклонить).
    user_applications_changes_result = await db.execute(
        select(EventParticipant.event_id, Event.title, func.count())
        .join(Event, EventParticipant.event_id == Event.id)
        .filter(
            EventParticipant.user_id == current_user,
            EventParticipant.approved.in_(
                [ApprovedType.APPROVED, ApprovedType.DENIED]
            ),
            EventParticipant.status_changed == True  # Только изменения статуса
        )
        .group_by(EventParticipant.event_id, Event.title)
    )
    user_applications_changes = user_applications_changes_result.all()

    # Приглашения от организаторов, ожидающие ответа пользователя.
    invitations_result = await db.execute(
        select(EventParticipant.event_id, Event.title)
        .join(Event, EventParticipant.event_id == Event.id)
        .filter(
            EventParticipant.user_id == current_user,
            EventParticipant.approved == ApprovedType.INVITED,
            EventParticipant.is_new == True,
        )
    )
    invitations = invitations_result.all()

    # Персистентные уведомления (например, отмена мероприятия) — переживают
    # удаление события, поэтому хранятся отдельно от EventParticipant.
    updates_result = await db.execute(
        select(UserNotification)
        .where(
            UserNotification.user_id == current_user,
            UserNotification.is_new == True
        )
        .order_by(UserNotification.created_at.desc())
    )
    event_updates = updates_result.scalars().all()

    # Формируем ответ
    return {
        "new_applications": [
            {
                "event_id": event_id,
                "event_title": organized_event_titles.get(event_id, "Мероприятие"),
                "count": count,
                "is_new": True  # Флаг для новых уведомлений
            }
            for event_id, count in new_applications
        ],
        "user_applications_changes": [
            {
                "event_id": event_id,
                "event_title": event_title,
                "count": count,
                "is_new": True  # Флаг для новых уведомлений
            }
            for event_id, event_title, count in user_applications_changes
        ],
        "invitations": [
            {
                "event_id": event_id,
                "event_title": event_title,
                "is_new": True,
            }
            for event_id, event_title in invitations
        ],
        "event_updates": [
            {
                "notification_id": n.id,
                "type": n.type,
                "title": n.title,
                "body": n.body,
                "is_new": n.is_new,
            }
            for n in event_updates
        ]
    }





@router.post("/profile/notifications/mark_as_read")
async def mark_notifications_as_read(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Сбрасываем флаг is_new для новых заявок
    await db.execute(
        update(EventParticipant)
        .where(
            EventParticipant.event_id.in_(
                select(Event.id)
                .where(Event.organizer_id == current_user)
            ),
            EventParticipant.is_new == True
        )
        .values(is_new=False)
    )

    # Сбрасываем флаг status_changed для изменений статуса
    await db.execute(
        update(EventParticipant)
        .where(
            EventParticipant.user_id == current_user,
            EventParticipant.status_changed == True
        )
        .values(status_changed=False)
    )

    # Сбрасываем персистентные уведомления пользователя.
    await db.execute(
        update(UserNotification)
        .where(
            UserNotification.user_id == current_user,
            UserNotification.is_new == True
        )
        .values(is_new=False)
    )

    await db.commit()
    return {"message": "Уведомления помечены как прочитанные"}


@router.post("/profile/notifications/mark_update_read")
async def mark_event_update_as_read(
    data: dict,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Помечает прочитанным одно персистентное уведомление (event_updates)."""
    notification_id = data.get('notification_id')
    if not notification_id:
        raise HTTPException(status_code=400, detail="Не указан notification_id")

    await db.execute(
        update(UserNotification)
        .where(
            UserNotification.id == notification_id,
            UserNotification.user_id == current_user,
        )
        .values(is_new=False)
    )
    await db.commit()
    return {"message": "Уведомление помечено как прочитанное"}

@router.post("/profile/notifications/mark_as_read_single")
async def mark_single_notification_as_read(
        data: dict,
        current_user: int = Depends(get_current_user_id),
        db: AsyncSession = Depends(get_db)
):
    event_id = data.get('event_id')
    notification_type = data.get('type')  # 'application' или 'change'

    if not event_id or not notification_type:
        raise HTTPException(status_code=400, detail="Неверные параметры")

    # Проверяем существование мероприятия
    event = await db.execute(select(Event).filter(Event.id == event_id))
    event = event.scalar()
    if not event:
        raise HTTPException(status_code=404, detail="Мероприятие не найдено")

    # Для новых заявок (организатор)
    if notification_type == 'application':
        # Проверяем, что текущий пользователь - организатор
        if event.organizer_id != current_user:
            raise HTTPException(status_code=403, detail="Недостаточно прав")

        # Сбрасываем флаг is_new для заявок этого мероприятия
        await db.execute(
            update(EventParticipant)
            .where(
                EventParticipant.event_id == event_id,
                EventParticipant.is_new == True
            )
            .values(is_new=False)
        )

    # Для изменений статуса заявок (участник)
    elif notification_type == 'change':
        # Сбрасываем флаг status_changed для заявок текущего пользователя
        await db.execute(
            update(EventParticipant)
            .where(
                EventParticipant.event_id == event_id,
                EventParticipant.user_id == current_user,
                EventParticipant.status_changed == True
            )
            .values(status_changed=False)
        )

    # Для приглашений (участник) — снимаем «новизну», само приглашение остаётся
    # активным, пока пользователь не примет/не отклонит его.
    elif notification_type == 'invitation':
        await db.execute(
            update(EventParticipant)
            .where(
                EventParticipant.event_id == event_id,
                EventParticipant.user_id == current_user,
                EventParticipant.approved == ApprovedType.INVITED,
                EventParticipant.is_new == True,
            )
            .values(is_new=False)
        )

    await db.commit()
    return {"message": "Уведомление помечено как прочитанное"}
