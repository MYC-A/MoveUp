#routes_profile.py
import uuid

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Request
from fastapi.templating import Jinja2Templates
from minio import Minio, S3Error
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func, update
from pathlib import Path
import os

from sqlalchemy.orm import selectinload, joinedload

from app.db.base import get_db
from app.event.dao_event import EventParticipantDAO
from app.event.models_event import Event, EventParticipant, ApprovedType
from app.lk.schemas_profile import EventsResponseAll
from app.posts.schemas_posts import PostInDB, PostInProfile
from app.users.models_user import User
from app.models.follow import UserFollow
from app.users.dependensies_user import get_current_user, get_current_user_id
from app.users.schemas_user import UserRead, UserUpdate
from app.posts.models_posts import Post, Comment
from app.posts.models_posts_like import PostLike
from typing import List
import io
from fastapi import Query

router = APIRouter(prefix="/profile", tags=["Profile"])

# Папка для шаблонов
templates = Jinja2Templates(directory="app/templates")

# Папка для хранения аватарок
AVATAR_DIR = Path("app/static/images/avatars")
AVATAR_DIR.mkdir(exist_ok=True)


MINIO_ENDPOINT = "localhost:9000"  # Адрес MinIO сервера
MINIO_ACCESS_KEY = "minioadmin"    # Логин для доступа к MinIO
MINIO_SECRET_KEY = "minioadmin"    # Пароль для доступа к MinIO
MINIO_BUCKET_NAME = "photos"       # Имя bucket для хранения фотографий

# Инициализация MinIO клиента
minio_client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=False  # Используйте True, если MinIO настроен с SSL
)

# Рендеринг страницы личного кабинета
@router.get("/")
async def get_profile_page(
    request: Request,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    format: str = Query("html", description="Формат ответа: html или json")
):
    # Получаем данные пользователя
    result = await db.execute(select(User).filter(User.id == current_user))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем статистику активности
    stats = await get_profile_stats(current_user, db)

    # Возвращаем JSON, если запрошен
    if format == "json":
        print("json")
        return {
            "user": {
                "id": user.id,
                "full_name": user.full_name,
                "bio": user.bio,
                "avatar_url": user.avatar_url,
                "total_subscriptions": user.total_subscriptions,  # Добавляем общее количество подписок
                "total_subscribers": user.total_subscribers,      # Добавляем общее количество подписчиков
            },
            "stats": stats,
        }

    # Возвращаем HTML по умолчанию
    return templates.TemplateResponse(
        "profile.html",
        {
            "request": request,
            "user": user,
            "stats": stats,
        }
    )


# Проверка существования бакета
try:
    if not minio_client.bucket_exists(MINIO_BUCKET_NAME):
        minio_client.make_bucket(MINIO_BUCKET_NAME)
except S3Error as e:
    print(f"Ошибка создания бакета: {e}")


# Обновление данных текущего пользователя
@router.put("/", response_model=UserRead)
async def update_profile(
        full_name: str = Form(None),
        bio: str = Form(None),
        avatar: UploadFile = File(None),
        current_user: int = Depends(get_current_user_id),
        db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(User).filter(User.id == current_user))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Обновляем данные пользователя
    if full_name:
        user.full_name = full_name
    if bio:
        user.bio = bio

    # Обработка аватарки
    if avatar:
        try:
            # Генерируем уникальное имя файла
            file_extension = avatar.filename.split('.')[-1] if avatar.filename else 'jpg'
            file_name = f"{current_user}_{uuid.uuid4()}.{file_extension}"

            # Читаем содержимое файла
            file_content = await avatar.read()

            # Загружаем в MinIO
            minio_client.put_object(
                MINIO_BUCKET_NAME,
                file_name,
                data=io.BytesIO(file_content),
                length=len(file_content),
                content_type=avatar.content_type or 'image/jpeg'
            )

            # Формируем URL для доступа к файлу
            avatar_url = f"http://{MINIO_ENDPOINT}/{MINIO_BUCKET_NAME}/{file_name}"
            user.avatar_url = avatar_url
        except S3Error as e:
            raise HTTPException(status_code=500, detail=f"Ошибка загрузки в MinIO: {e}")

    await db.commit()
    await db.refresh(user)
    return user

# Получение списка подписчиков
@router.get("/followers", response_model=dict)
async def get_followers(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Получаем список подписчиков с пагинацией
    followers_result = await db.execute(
        select(User)
        .join(UserFollow, UserFollow.follower_id == User.id)
        .filter(UserFollow.following_id == current_user)
        .offset(skip)
        .limit(limit)
    )
    followers = followers_result.scalars().all()

    # Преобразуем объекты SQLAlchemy в Pydantic-модели
    followers_data = [UserRead.from_orm(user) for user in followers]

    # Получаем общее количество подписчиков
    total_followers_result = await db.execute(
        select(func.count())
        .select_from(UserFollow)
        .filter(UserFollow.following_id == current_user)
    )
    total_followers = total_followers_result.scalar()

    return {
        "followers": followers_data,
        "total_followers": total_followers
    }
@router.get("/following", response_model=dict)
async def get_following(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Получаем список подписок с пагинацией
    following_result = await db.execute(
        select(User)
        .join(UserFollow, UserFollow.following_id == User.id)
        .filter(UserFollow.follower_id == current_user)
        .offset(skip)
        .limit(limit)
    )
    following = following_result.scalars().all()

    # Преобразуем объекты SQLAlchemy в Pydantic-модели
    following_data = [UserRead.from_orm(user) for user in following]

    # Получаем общее количество подписок
    total_following_result = await db.execute(
        select(func.count())
        .select_from(UserFollow)
        .filter(UserFollow.follower_id == current_user)
    )
    total_following = total_following_result.scalar()

    return {
        "following": following_data,
        "total_following": total_following
    }

# Получение статистики активности
@router.get("/stats", response_model=dict)
async def get_profile_stats(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Количество постов
    posts_count = await db.execute(select(func.count()).where(Post.user_id == current_user))
    posts_count = posts_count.scalar()

    # Количество комментариев
    comments_count = await db.execute(select(func.count()).where(Comment.user_id == current_user))
    comments_count = comments_count.scalar()

    # Количество лайков
    likes_count = await db.execute(select(func.count()).where(PostLike.user_id == current_user))
    likes_count = likes_count.scalar()

    return {
        "posts_count": posts_count,
        "comments_count": comments_count,
        "likes_count": likes_count
    }



@router.get("/events", response_model=EventsResponseAll)
async def get_user_events(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Получаем мероприятия текущего пользователя
    result = await db.execute(
        select(Event)
        .filter(Event.organizer_id == current_user)
        .offset(skip)
        .limit(limit)
    )
    events = result.scalars().all()

    # Преобразуем данные в JSON-совместимый формат
    events_data = []
    for event in events:
        events_data.append({
            "id": event.id,
            "title": event.title,
            "description": event.description,
            "start_time": event.start_time,
            "end_time": event.end_time
        })

    return {"events": events_data}

@router.get("/{user_id}", response_model=UserRead)
async def get_user_profile(
    user_id: int,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Получаем данные пользователя
    result = await db.execute(select(User).filter(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем статистику активности
    stats = await get_profile_stats(user_id, db)

    # Получаем подписчиков и подписки
    followers = await get_followers(user_id, db, skip=0, limit=10)
    following = await get_following(user_id, db, skip=0, limit=10)

    return {
        "user": user,
        "stats": stats,
        "followers": followers,
        "following": following
    }


@router.get("/view/{user_id}")
async def view_user_profile(
    request: Request,
    user_id: int,
    db: AsyncSession = Depends(get_db),
    format: str = Query("html", description="Формат ответа: html или json")
):
    # Получаем данные пользователя
    result = await db.execute(select(User).filter(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем статистику активности
    stats = await get_profile_stats(user_id, db)

    # Получаем подписчиков и подписки
    followers = await get_followers(user_id, db, skip=0, limit=10)
    following = await get_following(user_id, db, skip=0, limit=10)

    # Возвращаем JSON, если запрошен
    if format == "json":
        return {
            "user": {
                "id": user.id,
                "full_name": user.full_name,
                "bio": user.bio,
                "avatar_url": user.avatar_url
            },
            "stats": stats,
            "followers": followers,
            "following": following
        }

    # Возвращаем HTML по умолчанию
    return templates.TemplateResponse(
        "profile_view.html",
        {
            "request": request,
            "user": user,
            "stats": stats,
            "followers": followers,
            "following": following
        }
    )

@router.get("/{user_id}/posts", response_model=List[PostInProfile])
async def get_user_posts(
    user_id: int,
    skip: int = 0,
    limit: int = 20,
    current_user_id: int = Depends(get_current_user_id),  # Добавляем текущего пользователя
    db: AsyncSession = Depends(get_db)
):
    # Загружаем посты вместе с пользователем и фотографиями
    stmt = select(Post).options(
        selectinload(Post.user),
        selectinload(Post.photos)  # Загружаем фотографии
    ).filter(Post.user_id == user_id) \
     .order_by(Post.created_at.desc()) \
     .offset(skip) \
     .limit(limit)

    result = await db.execute(stmt)
    posts = result.scalars().all()

    posts_data = []
    for post in posts:
        # Проверяем, лайкнул ли текущий пользователь этот пост
        like_stmt = select(PostLike).filter(
            PostLike.user_id == current_user_id,
            PostLike.post_id == post.id
        )
        like_result = await db.execute(like_stmt)
        liked_by_current_user = like_result.scalars().first() is not None

        # Получаем URL фотографий
        photo_urls = [photo.photo_url for photo in post.photos]

        # Формируем данные поста
        post_data = {
            "id": post.id,
            "content": post.content,
            "distance": post.distance,
            "duration": post.duration,
            "route_data": post.route_data,
            "user_id": post.user_id,
            "likes_count": post.likes_count,
            "comments_count": post.comments_count,
            "created_at": post.created_at,
            "liked_by_current_user": liked_by_current_user,  # Добавляем информацию о лайке
            "user": {
                "id": post.user.id,
                "full_name": post.user.full_name,
                "avatar_url": post.user.avatar_url
            },
            "photo_urls": photo_urls  # Добавляем URL фотографий
        }
        posts_data.append(post_data)

    return posts_data


from pydantic import BaseModel
from typing import List, Optional

class ApplicationResponse(BaseModel):
    id: int
    user_id: int
    user_name: str
    user_avatar:  Optional[str] = None  # Поле может быть None
    status: str

class EventApplicationsResponse(BaseModel):
    applications: List[ApplicationResponse]
    total_applications: int




@router.get("/event/{event_id}/applications", response_model=EventApplicationsResponse)
async def get_event_applications(
    event_id: int,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Проверяем, что текущий пользователь является организатором события
    event_result = await db.execute(select(Event).filter(Event.id == event_id, Event.organizer_id == current_user))
    event = event_result.scalars().first()
    if not event:
        raise HTTPException(status_code=404, detail="Событие не найдено или вы не являетесь организатором")

    # Получаем заявки на событие, которые еще не были одобрены или отклонены
    result = await db.execute(
        select(EventParticipant)
        .filter(EventParticipant.event_id == event_id, EventParticipant.approved == ApprovedType.AWAITS)
        .options(selectinload(EventParticipant.user))  # Загружаем данные пользователя
        .offset(skip)
        .limit(limit)
    )
    applications = result.scalars().all()

    # Преобразуем данные в JSON-совместимый формат
    applications_data = []
    for app in applications:
        applications_data.append({
            "id": app.id,
            "user_id": app.user_id,
            "user_name": app.user.full_name,
            "user_avatar": app.user.avatar_url or "/static/images/default-avatar.png",  # Значение по умолчанию
            "status": app.approved.value  # Статус заявки (например, "AWAITS", "APPROVED", "DENIED")
        })

    # Получаем общее количество заявок
    total_applications = await db.execute(
        select(func.count())
        .select_from(EventParticipant)
        .filter(EventParticipant.event_id == event_id, EventParticipant.approved == ApprovedType.AWAITS)
    )
    total_applications = total_applications.scalar()

    return {
        "applications": applications_data,
        "total_applications": total_applications
    }


@router.post("/event/{event_id}/applications/{participant_id}/approve")
async def approve_application(
    event_id: int,
    participant_id: int,
    db: AsyncSession = Depends(get_db),
):
    try:
        # Обновляем статус участника
        participant = await EventParticipantDAO.update_participant(
            participant_id=participant_id,
            event_id=event_id,
            new_status=ApprovedType.APPROVED,
            session=db,
        )
        # Получаем мероприятие по ID
        event = await db.get(Event, event_id)
        if not event:
            raise ValueError("Мероприятие не найдено")
        # Возвращаем данные мероприятия
        return {
            "id": event.id,
            "title": event.title,
            "group_chat_id": event.group_chat_id,  # Может быть null
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail="Внутренняя ошибка сервера")

@router.post("/event/{event_id}/applications/{participant_id}/reject")
async def reject_application(
    event_id: int,
    participant_id: int,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    try:
        await EventParticipantDAO.update_participant(
            participant_id=participant_id,
            event_id=event_id,
            new_status=ApprovedType.DENIED,
            session=db
        )
        return {"message": "Заявка отклонена"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/profile/notifications", response_model=dict)
async def get_user_notifications(
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Получаем мероприятия, которые организовал текущий пользователь
    organized_events = await db.execute(
        select(Event.id, Event.title)  # Выбираем ID и название мероприятий
        .filter(Event.organizer_id == current_user)
    )
    organized_events = organized_events.all()  # Получаем список кортежей (id, title)

    # Получаем новые заявки на мероприятия, которые организовал пользователь
    new_applications = await db.execute(
        select(EventParticipant.event_id, func.count())
        .filter(
            EventParticipant.event_id.in_([event.id for event in organized_events]),
            EventParticipant.approved == ApprovedType.AWAITS,
            EventParticipant.is_new == True  # Только новые заявки
        )
        .group_by(EventParticipant.event_id)
    )
    new_applications = new_applications.all()  # Список кортежей (event_id, count)

    # Получаем изменения в статусе заявок, которые подал пользователь
    user_applications_changes = await db.execute(
        select(EventParticipant.event_id, func.count())
        .filter(
            EventParticipant.user_id == current_user,
            EventParticipant.approved != ApprovedType.AWAITS,
            EventParticipant.status_changed == True  # Только изменения статуса
        )
        .group_by(EventParticipant.event_id)
    )
    user_applications_changes = user_applications_changes.all()  # Список кортежей (event_id, count)

    # Формируем ответ
    return {
        "new_applications": [
            {
                "event_id": event_id,
                "event_title": next(event.title for event in organized_events if event.id == event_id),
                "count": count,
                "is_new": True  # Флаг для новых уведомлений
            }
            for event_id, count in new_applications
        ],
        "user_applications_changes": [
            {
                "event_id": event_id,
                "event_title": next(event.title for event in organized_events if event.id == event_id),
                "count": count,
                "is_new": True  # Флаг для новых уведомлений
            }
            for event_id, count in user_applications_changes
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

    await db.commit()
    return {"message": "Уведомления помечены как прочитанные"}

@router.put("/", response_model=UserRead)
async def update_profile(
    full_name: str = Form(None),
    bio: str = Form(None),
    avatar: UploadFile = File(None),
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(User).filter(User.id == current_user))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    if full_name:
        user.full_name = full_name
    if bio:
        user.bio = bio

    if avatar:
        avatar_path = AVATAR_DIR / f"{current_user}.jpg"
        with open(avatar_path, "wb") as buffer:
            buffer.write(await avatar.read())
        user.avatar_url = f"/static/images/avatars/{current_user}.jpg"

    await db.commit()
    await db.refresh(user)
    return user

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

    await db.commit()
    return {"message": "Уведомление помечено как прочитанное"}


@router.get("/user/applications", response_model=dict)

async def get_user_applications(
    skip: int = 0,
    limit: int = 10,
    user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    query = (
        select(EventParticipant)
        .options(joinedload(EventParticipant.event))  # Загружаем связанные мероприятия
        .filter(EventParticipant.user_id == user_id)
        .order_by(EventParticipant.id.desc())  # Новые заявки сверху
        .offset(skip)
        .limit(limit)
    )

    result = await db.execute(query)
    applications = result.scalars().all()

    return {
        "applications": [
            {
                "id": app.id,
                "event_id": app.event.id,
                "event_title": app.event.title,
                "event_date": app.event.start_time.strftime("%Y-%m-%d"),
                "status": app.approved.value
            }
            for app in applications
        ],
        "has_more": len(applications) == limit
    }
@router.get("/{user_id}/followers", response_model=dict)
async def get_followers_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Получаем данные пользователя
    user_result = await db.execute(select(User).filter(User.id == user_id))
    user = user_result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем список подписчиков с пагинацией
    followers_result = await db.execute(
        select(User)
        .join(UserFollow, UserFollow.follower_id == User.id)
        .filter(UserFollow.following_id == user_id)
        .offset(skip)
        .limit(limit)
    )
    followers = followers_result.scalars().all()

    # Преобразуем объекты SQLAlchemy в Pydantic-модели
    followers_data = [UserRead.from_orm(user) for user in followers]

    return {
        "followers": followers_data,
        "total_followers": user.total_subscribers,  # Используем значение из таблицы User
        "total_subscriptions": user.total_subscriptions,  # Используем значение из таблицы User
    }


@router.get("/{user_id}/following", response_model=dict)
async def get_following_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(10, ge=1, le=100)
):
    # Получаем данные пользователя
    user_result = await db.execute(select(User).filter(User.id == user_id))
    user = user_result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем список подписок с пагинацией
    following_result = await db.execute(
        select(User)
        .join(UserFollow, UserFollow.following_id == User.id)
        .filter(UserFollow.follower_id == user_id)
        .offset(skip)
        .limit(limit)
    )
    following = following_result.scalars().all()

    # Преобразуем объекты SQLAlchemy в Pydantic-модели
    following_data = [UserRead.from_orm(user) for user in following]

    return {
        "following": following_data,
        "total_following": user.total_subscriptions,  # Используем значение из таблицы User
        "total_subscribers": user.total_subscribers,  # Используем значение из таблицы User
    }

"""
# Рендеринг страницы личного кабинета
@router.get("/")
async def get_profile_page(
    request: Request,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    format: str = Query("html", description="Формат ответа: html или json")
):
    # Получаем данные пользователя
    result = await db.execute(select(User).filter(User.id == current_user))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Получаем статистику активности
    stats = await get_profile_stats(current_user, db)

    # Получаем подписчиков и подписки
    followers = await get_followers(current_user, db, skip=0, limit=10)
    following = await get_following(current_user, db, skip=0, limit=10)

    # Возвращаем JSON, если запрошен
    if format == "json":
        print("json")
        return {
            "user": {
                "id": user.id,
                "full_name": user.full_name,
                "bio": user.bio,
                "avatar_url": user.avatar_url
            },
            "stats": stats,
            "followers": followers,
            "following": following
        }

    # Возвращаем HTML по умолчанию
    return templates.TemplateResponse(
        "profile.html",
        {
            "request": request,
            "user": user,
            "stats": stats,
            "followers": followers,
            "following": following
        }
    )

"""
