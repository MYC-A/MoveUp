# app/api/routes/posts.py
import asyncio
import io
import json
import uuid
from datetime import timedelta
from typing import List, Dict, Optional

from fastapi.security import OAuth2PasswordRequestForm
from minio import Minio, S3Error
from sqlalchemy import select, delete, or_, and_, func, update
from sqlalchemy.exc import IntegrityError
from app.models.follow import UserFollow
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session, selectinload
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Request, Depends, HTTPException, status, UploadFile, File, Form, Query

from fastapi.templating import Jinja2Templates
from starlette.websockets import WebSocketState
from fastapi.responses import JSONResponse
from app.users.dependensies_user import get_current_user, get_current_user_id
from app.core.config import settings
from app.core.uploads import validate_image_upload
from app.db.base import get_db
from app.users.auth_users import create_access_token
from app.users.models_user import User
from app.posts.models_posts_comments import Comment
from app.posts.models_posts_like import PostLike
from .schemas_comments import CommentCreate
from .schemas_posts import PostCreate, PostInDB
from .models_posts import Post, PostPhoto
from ..users.auth_users import authenticate_user

router = APIRouter(prefix='/post', tags=['Post'])
templates = Jinja2Templates(directory='app/templates')

# Активные WebSocket-подключения для ленты новостей
active_feed_connections: List[WebSocket] = []

# Активные WebSocket-подключения для отдельных постов


# WebSocket эндпоинт для ленты новостей
@router.websocket("/ws/feed")
async def websocket_feed(websocket: WebSocket):
    await websocket.accept()
    active_feed_connections.append(websocket)
    print(f"WebSocket для ленты новостей открыт: {len(active_feed_connections)}")

          # Здесь можно вызывать методы или свойства connection

    try:
        while True:
            # Ожидаем сообщения от клиента (или просто держим соединение открытым)
            await websocket.receive_text()
    except WebSocketDisconnect:
        # Удаляем соединение при отключении клиента
        active_feed_connections.remove(websocket)
        print(f"WebSocket для ленты новостей закрыт:{len(active_feed_connections)}")


    except Exception as e:
        # Логируем любые другие ошибки
        print(f"Ошибка в WebSocket: {e}")
        active_feed_connections.remove(websocket)
    finally:
        # Убедимся, что соединение удалено из списка
        if websocket in active_feed_connections:
            active_feed_connections.remove(websocket)


# WebSocket эндпоинт для отдельных постов
active_post_connections = {}

@router.websocket("/ws/post/{post_id}")
async def websocket_post(websocket: WebSocket, post_id: int):
    # Принимаем соединение
    await websocket.accept()
    print(f"Новое подключение к посту {post_id}")

    # Инициализация списка подключений для поста, если его еще нет
    if post_id not in active_post_connections:
        active_post_connections[post_id] = []

    # Добавляем текущее соединение в список
    active_post_connections[post_id].append(websocket)
    print(f"Активных подключений к посту {post_id}: {len(active_post_connections[post_id])}")

    try:
        while True:
            # Ожидаем сообщение от клиента
            data = await websocket.receive_text()
            print(f"Сообщение от клиента (пост {post_id}): {data}")

            # Пример: Отправка сообщения всем подключенным клиентам этого поста
            for connection in active_post_connections[post_id]:
                await connection.send_text(f"Сообщение для поста {post_id}: {data}")

    except WebSocketDisconnect:
        # Клиент отключился
        print(f"Клиент отключился от поста {post_id}")
        active_post_connections[post_id].remove(websocket)

        # Если больше нет подключений к этому посту, удаляем запись из словаря
        if not active_post_connections[post_id]:
            del active_post_connections[post_id]
            print(f"Нет активных подключений к посту {post_id}")
        else:
            print(f"Активных подключений к посту {post_id}: {len(active_post_connections[post_id])}")

    except Exception as e:
        # Обработка других ошибок
        print(f"Ошибка в WebSocket (пост {post_id}): {e}")
        active_post_connections[post_id].remove(websocket)

        # Если больше нет подключений к этому посту, удаляем запись из словаря
        if not active_post_connections[post_id]:
            del active_post_connections[post_id]
            print(f"Нет активных подключений к посту {post_id}")


# Функция для отправки обновлений в ленту новостей
async def broadcast_feed_update(update: dict):
    for connection in active_feed_connections[:]:  # Используем копию списка, чтобы избежать изменений во время итерации
        try:
            # Проверяем состояние соединения
            if connection.client_state == WebSocketState.CONNECTED:
                await connection.send_json(update)
            else:
                # Удаляем соединение, если оно закрыто
                active_feed_connections.remove(connection)
        except RuntimeError as e:
            if "Cannot call 'send' once a close message has been sent" in str(e):
                # Удаляем соединение, если оно закрыто
                active_feed_connections.remove(connection)
            else:
                # Логируем другие ошибки
                print(f"Ошибка при отправке сообщения: {e}")
        except Exception as e:
            # Логируем любые другие исключения
            print(f"Неожиданная ошибка: {e}")
            active_feed_connections.remove(connection)


# Функция для отправки обновлений для конкретного поста
async def broadcast_post_update(post_id: int, update: dict):
    if post_id in active_post_connections:
        for connection in active_post_connections[post_id][:]:
            try:
                if connection.client_state == WebSocketState.CONNECTED:
                    await connection.send_json(update)
                else:
                    active_post_connections[post_id].remove(connection)
            except RuntimeError as e:
                if "Cannot call 'send' once a close message has been sent" in str(e):
                    active_post_connections[post_id].remove(connection)
                else:
                    print(f"Ошибка при отправке сообщения: {e}")
            except Exception as e:
                print(f"Неожиданная ошибка: {e}")
                active_post_connections[post_id].remove(connection)


@router.get("/feed", response_model=List[PostInDB])
async def get_feed(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    scope: str = Query("all", description="Режим ленты: all, following или mine"),
    q: Optional[str] = Query(None, description="Поиск по тексту, городу или автору"),
    city: Optional[str] = Query(None, description="Фильтр по городу поста"),
    has_route: Optional[bool] = Query(None, description="Посты с маршрутом / без маршрута"),
    with_photos: Optional[bool] = Query(None, description="Посты с фото / без фото"),
    current_user1=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Лента активности.

    По умолчанию показываем свежие посты сообщества. Режим following оставляет
    только текущего пользователя и его подписки, mine — только текущего
    пользователя.
    """
    current_user = current_user1.id
    scope = (scope or "all").strip().lower()
    if scope not in {"all", "following", "mine"}:
        raise HTTPException(status_code=400, detail="Invalid feed scope")

    stmt_posts = (
        select(Post)
        .options(selectinload(Post.user), selectinload(Post.photos))  # Загружаем фотографии
        .outerjoin(User, Post.user_id == User.id)
        .order_by(Post.created_at.desc(), Post.id.desc())  # Стабильная сортировка для offset/limit
    )

    if scope == "following":
        following_subq = select(UserFollow.following_id).where(
            UserFollow.follower_id == current_user
        )
        stmt_posts = stmt_posts.where(
            or_(
                Post.user_id == current_user,
                Post.user_id.in_(following_subq),
            )
        )
    elif scope == "mine":
        stmt_posts = stmt_posts.where(Post.user_id == current_user)

    if q and q.strip():
        search = f"%{q.strip()}%"
        stmt_posts = stmt_posts.where(
            or_(
                Post.content.ilike(search),
                Post.city.ilike(search),
                User.full_name.ilike(search),
                User.username.ilike(search),
            )
        )

    if city and city.strip():
        stmt_posts = stmt_posts.where(Post.city.ilike(f"%{city.strip()}%"))

    if has_route is True:
        stmt_posts = stmt_posts.where(
            or_(Post.distance > 0, Post.duration > 0)
        )
    elif has_route is False:
        stmt_posts = stmt_posts.where(
            and_(
                or_(Post.distance == 0, Post.distance.is_(None)),
                or_(Post.duration == 0, Post.duration.is_(None)),
            )
        )

    if with_photos is True:
        stmt_posts = stmt_posts.where(Post.photos.any())
    elif with_photos is False:
        stmt_posts = stmt_posts.where(~Post.photos.any())

    stmt_posts = stmt_posts.offset(skip).limit(limit)
    result_posts = await db.execute(stmt_posts)
    posts = result_posts.scalars().all()

    # Проверяем, лайкнул ли текущий пользователь каждый пост
    post_ids = [post.id for post in posts]
    liked_post_ids = set()
    if post_ids:
        result = await db.execute(
            select(PostLike.post_id).where(
                PostLike.user_id == current_user,
                PostLike.post_id.in_(post_ids)
            )
        )
        liked_post_ids = set(result.scalars().all())

    for post in posts:
        post.liked_by_current_user = post.id in liked_post_ids
        post.photo_urls = [photo.photo_url for photo in post.photos]

    # Преобразуем посты в JSON
    posts_json = [
        {
            "id": post.id,
            "user_id": post.user_id,
            "content": post.content,
            "distance": post.distance,
            "duration": post.duration,
            "city": post.city,
            "route_data": post.route_data,
            "likes_count": post.likes_count,
            "comments_count": post.comments_count,
            "created_at": post.created_at.isoformat(),
            "user": {
                "id": post.user.id,
                "full_name": post.user.full_name,
                "avatar_url": post.user.avatar_url,
            },
            "liked_by_current_user": post.liked_by_current_user,
            "photo_urls": post.photo_urls,
        }
        for post in posts
    ]

    return JSONResponse(content=posts_json)


# Инициализация MinIO клиента
minio_client = Minio(
    settings.MINIO_ENDPOINT,
    access_key=settings.MINIO_ACCESS_KEY,
    secret_key=settings.MINIO_SECRET_KEY,
    secure=False  # Используйте True, если MinIO настроен с SSL
)

async def check():
    # Проверка и создание бакета, если он не существует
    bucket_name = settings.MINIO_POSTS_BUCKET_NAME
    if not minio_client.bucket_exists(bucket_name):
        minio_client.make_bucket(bucket_name)
        print(f"Bucket '{bucket_name}' created.")
    else:
        print(f"Bucket '{bucket_name}' already exists.")
async def upload_photo_to_minio(file: UploadFile, bucket_name: str):
    await check()

    # Читаем и валидируем файл до загрузки (тип/размер/сигнатура).
    file_content = await file.read()
    validate_image_upload(file, file_content)

    try:
        # Генерируем уникальное имя файла
        file_name = f"{uuid.uuid4()}_{file.filename}"

        # Загружаем файл в MinIO
        minio_client.put_object(
            bucket_name,
            file_name,
            io.BytesIO(file_content),
            length=len(file_content),
            content_type=file.content_type or "image/jpeg"
        )

        # Возвращаем URL файла
        return f"{settings.MINIO_PUBLIC_URL.rstrip('/')}/{bucket_name}/{file_name}"
    except S3Error as e:
        print(f"Error uploading file to MinIO: {e}")
        raise

@router.post("/posts_create", response_model=PostInDB)
async def create_post(
    post: str = Form(...),  # Принимаем PostCreate как JSON-строку
    # Фото необязательны: пост может быть без фотографий (раньше отсутствие
    # photos давало 422 Unprocessable Entity).
    photos: Optional[List[UploadFile]] = File(None),
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    # Преобразуем JSON-строку в объект PostCreate
    try:
        post_data = json.loads(post)
        post_create = PostCreate(**post_data)
    except (json.JSONDecodeError, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid PostCreate data: {e}")

    # Преобразуем route_data: datetime -> строка (если требуется)
    post_dict = post_create.dict()
    post_dict["route_data"] = [
        {
            **point,
            "timestamp": point["timestamp"].replace(tzinfo=None).isoformat()
        }
        for point in post_dict["route_data"]
    ]
    post_dict["user_id"] = current_user

    # Создаем запись в базе данных
    db_post = Post(**post_dict)
    db.add(db_post)
    await db.commit()
    await db.refresh(db_post)

    # Сохраняем загруженные фотографии в MinIO (если есть)
    photo_urls = []
    for photo in (photos or []):
        photo_url = await upload_photo_to_minio(photo, settings.MINIO_POSTS_BUCKET_NAME)
        db_photo = PostPhoto(post_id=db_post.id, photo_url=photo_url)
        db.add(db_photo)
        photo_urls.append(photo_url)

    await db.commit()

    await broadcast_feed_update({
        "type": "post_created",
        "post_id": db_post.id,
        "user_id": current_user,
    })

    # Возвращаем созданный пост с фотографиями
    return {**db_post.__dict__, "photos": photo_urls}





@router.post("/posts/{post_id}/like")
async def like_post(
        post_id: int,
        current_user1: str = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    # Проверяем, существует ли пост
    result = await db.execute(select(Post).filter(Post.id == post_id))
    post = result.scalars().first()
    current_user = current_user1

    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")

    # Проверяем, лайкал ли уже пользователь этот пост
    result = await db.execute(
        select(PostLike).filter(
            PostLike.user_id == current_user.id,
            PostLike.post_id == post_id
        )
    )
    existing_like = result.scalars().first()

    if existing_like:
        await db.delete(existing_like)
        liked = False
    else:
        new_like = PostLike(user_id=current_user.id, post_id=post_id)
        db.add(new_like)
        try:
            await db.flush()
        except IntegrityError:
            # Конкурентный дублирующий запрос — откатываемся, считаем реальный счётчик
            await db.rollback()
            count_res = await db.execute(
                select(func.count()).where(PostLike.post_id == post_id)
            )
            actual_count = count_res.scalar() or 0
            return {"likes_count": actual_count, "liked": True}
        liked = True

    # Пересчитываем из источника истины — post_likes — чтобы счётчик всегда был точным
    # независимо от конкурентных запросов и старых данных.
    count_res = await db.execute(
        select(func.count()).where(PostLike.post_id == post_id)
    )
    actual_count = count_res.scalar() or 0

    await db.execute(
        update(Post).where(Post.id == post_id).values(likes_count=actual_count)
    )
    await db.commit()
    await db.refresh(post)

    # Отправляем обновление через WebSocket
    await broadcast_feed_update({
        "type": "like",
        "post_id": post_id,
        "likes_count": actual_count,
        "liked": liked,
        "user_id": current_user.id
    })

    await broadcast_post_update(post_id, {
        "type": "like",
        "post_id": post_id,
        "likes_count": actual_count,
        "liked": liked,
        "user_id": current_user.id
    })

    return {"likes_count": actual_count, "liked": liked}


@router.post("/posts/{post_id}/create_comment")
async def add_comment(
        post_id: int,
        comment: CommentCreate,
        current_user: str = Depends(get_current_user),
        db: Session = Depends(get_db)
):
    # Проверяем, существует ли пост
    result = await db.execute(select(Post).filter(Post.id == post_id))
    post = result.scalars().first()
    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")

    # Добавляем комментарий
    new_comment = Comment(
        user_id=current_user.id,
        post_id=post_id,
        content=comment.content
    )
    db.add(new_comment)
    post.comments_count += 1
    await db.commit()
    await db.refresh(new_comment)

    # Формируем данные для отправки через WebSocket
    comment_data = {
        "type": "comment",
        "post_id": post_id,
        "comments_count": post.comments_count,
        "comment": {
            "id": new_comment.id,
            "user_id": new_comment.user_id,
            "content": new_comment.content,
            "created_at": new_comment.created_at.isoformat(),
            "user": {
                "username": current_user.full_name,
                "full_name": current_user.full_name,
                "avatar_url": current_user.avatar_url,
            }
        }
    }

    # Отправляем комментарий через WebSocket
    await broadcast_feed_update(comment_data)
    await broadcast_post_update(post_id, comment_data)

    return comment_data["comment"]


@router.delete("/posts/{post_id}/comments/{comment_id}")
async def delete_comment(
    post_id: int,
    comment_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Удаляет комментарий. Может автор комментария или владелец поста."""
    result = await db.execute(select(Post).filter(Post.id == post_id))
    post = result.scalars().first()
    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")

    comment_result = await db.execute(
        select(Comment).filter(Comment.id == comment_id, Comment.post_id == post_id)
    )
    comment = comment_result.scalars().first()
    if not comment:
        raise HTTPException(status_code=404, detail="Комментарий не найден")

    if comment.user_id != current_user.id and post.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Нет прав на удаление комментария")

    await db.delete(comment)
    if post.comments_count and post.comments_count > 0:
        post.comments_count -= 1
    await db.commit()

    update = {
        "type": "comment_deleted",
        "post_id": post_id,
        "comment_id": comment_id,
        "comments_count": post.comments_count,
    }
    await broadcast_feed_update(update)
    await broadcast_post_update(post_id, update)
    return {"status": "ok", "comments_count": post.comments_count}


@router.delete("/posts/{post_id}")
async def delete_post(
    post_id: int,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Удаляет пост владельца вместе со связанными лайками/комментариями/фото."""
    result = await db.execute(select(Post).filter(Post.id == post_id))
    post = result.scalars().first()
    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")
    if post.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Нет прав на удаление поста")

    # Удаляем зависимые записи, чтобы не нарушить внешние ключи.
    await db.execute(delete(Comment).where(Comment.post_id == post_id))
    await db.execute(delete(PostLike).where(PostLike.post_id == post_id))
    await db.execute(delete(PostPhoto).where(PostPhoto.post_id == post_id))
    await db.delete(post)
    await db.commit()

    await broadcast_feed_update({"type": "post_deleted", "post_id": post_id})
    return {"status": "ok", "deleted_post_id": post_id}


@router.get("/posts/{post_id}/comments")
async def get_comments(
    post_id: int,
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Post).filter(Post.id == post_id))
    post = result.scalars().first()
    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")

    result = await db.execute(
        select(Comment)
        .filter(Comment.post_id == post_id)
        .options(selectinload(Comment.user))
        .order_by(Comment.created_at.asc(), Comment.id.asc())
        .offset(skip)
        .limit(limit)
    )
    comments = result.scalars().all()

    return [
        {
            "id": comment.id,
            "user_id": comment.user_id,
            "content": comment.content,
            "created_at": comment.created_at.isoformat(),
            "user": {
                "username": comment.user.full_name,
                "full_name": comment.user.full_name,
                "avatar_url": comment.user.avatar_url,
            }
        }
        for comment in comments
    ]

@router.get("/posts/{post_id}/details")
async def get_post_details(
    post_id: int,
    current_user1=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Получить данные поста для всплывающего окна"""
    # Получаем пост
    result = await db.execute(
        select(Post)
        .options(selectinload(Post.user), selectinload(Post.photos))  # Загружаем фотографии
        .filter(Post.id == post_id)
    )
    post = result.scalars().first()
    if not post:
        raise HTTPException(status_code=404, detail="Пост не найден")

    # Проверяем, лайкнул ли текущий пользователь этот пост
    result = await db.execute(
        select(PostLike).filter(
            PostLike.user_id == current_user1.id,
            PostLike.post_id == post_id
        )
    )
    post.liked_by_current_user = result.scalars().first() is not None

    # Получаем URL фотографий
    photo_urls = [photo.photo_url for photo in post.photos]

    return {
        "post": {
            "id": post.id,
            "user_id": post.user_id,
            "content": post.content,
            "distance": post.distance,
            "duration": post.duration,
            "city": post.city,
            "route_data": post.route_data,
            "likes_count": post.likes_count,
            "comments_count": post.comments_count,
            "created_at": post.created_at.isoformat(),
            "user": {
                "id": post.user.id,
                "full_name": post.user.full_name,
                "avatar_url": post.user.avatar_url
            },
            "liked_by_current_user": post.liked_by_current_user,
            "photo_urls": photo_urls  # Добавляем URL фотографий
        }
    }


@router.get("/posts/{post_id}/view")
async def view_post_with_comments(
        post_id: int,
        request: Request,
        current_user1=Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    """Получить страницу с постом и комментариями"""
    # Получаем данные поста
    post_details = await get_post_details(post_id, current_user1, db)

    # Получаем первые комментарии
    comments = await get_comments(post_id, skip=0, limit=10, db=db)

    return templates.TemplateResponse(
        "post_details.html",
        {
            "request": request,
            "post": post_details["post"],
            "comments": comments,
            "current_user_id": current_user1.id
        }
    )


@router.post("/token")
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    # Аутентификация пользователя
    user = await authenticate_user(email=form_data.username, password=form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # Создание токена
    access_token = create_access_token(data={"sub": str(user.id)}, expires_delta=timedelta(minutes=30))
    return {"access_token": access_token, "token_type": "bearer"}
