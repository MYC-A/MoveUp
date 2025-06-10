# app/api/routes/posts.py
import asyncio
import json
import uuid
from datetime import timedelta
from typing import List, Dict

from fastapi.security import OAuth2PasswordRequestForm
from minio import Minio, S3Error
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session, selectinload
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Request, Depends, HTTPException, status, UploadFile,File,Form

from fastapi.templating import Jinja2Templates
from starlette.websockets import WebSocketState
from fastapi.responses import JSONResponse
from app.users.dependensies_user import get_current_user, get_current_user_id
from app.db.base import get_db
from app.core.security import create_access_token
from app.models.follow import UserFollow
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
    skip: int = 0,
    limit: int = 20,
    current_user1=Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Получить ленту активности с постами от друзей и рекомендациями"""
    current_user = current_user1.id

    # Получаем посты от друзей (исключая посты текущего пользователя)
    stmt_friends = (
        select(Post)
        .options(selectinload(Post.user), selectinload(Post.photos))  # Загружаем фотографии


        .order_by(Post.created_at.desc())  # Сортируем по новизне
        .offset(skip)
        .limit(limit)
    )
    """
    .join(UserFollow, UserFollow.following_id == Post.user_id)
            .filter(
            UserFollow.follower_id == current_user,
            Post.user_id != current_user  # Исключаем посты текущего пользователя
        )
    """
    result_friends = await db.execute(stmt_friends)
    friend_posts = result_friends.scalars().all()

    # Получаем рекомендации (посты от пользователей, на которых не подписан текущий пользователь)
    stmt_recommendations = (
        select(Post)
        .options(selectinload(Post.user), selectinload(Post.photos))  # Загружаем фотографии
        .outerjoin(UserFollow, (UserFollow.following_id == Post.user_id) & (UserFollow.follower_id == current_user))
        .filter(
            UserFollow.follower_id.is_(None),  # Посты от пользователей, на которых не подписан
            Post.user_id != current_user  # Исключаем посты текущего пользователя
        )
        .order_by(
            Post.likes_count.desc(),  # Сортируем по популярности
            Post.created_at.desc()    # Затем по новизне
        )
        .offset(skip)
        .limit(limit)
    )
    result_recommendations = await db.execute(stmt_recommendations)
    recommended_posts = result_recommendations.scalars().all()

    # Объединяем посты от друзей и рекомендации
    all_posts = friend_posts + recommended_posts

    # Убираем дубликаты (если пост от друга также попал в рекомендации)
    unique_posts = list({post.id: post for post in all_posts}.values())

    # Сортируем объединенный список по дате создания
    unique_posts.sort(key=lambda post: post.created_at, reverse=True)

    # Проверяем, лайкнул ли текущий пользователь каждый пост
    for post in unique_posts:
        result = await db.execute(
            select(PostLike).filter(
                PostLike.user_id == current_user1.id,
                PostLike.post_id == post.id
            )
        )
        post.liked_by_current_user = result.scalars().first() is not None

    for post in unique_posts:
        post.photo_urls = [photo.photo_url for photo in post.photos]

    # Преобразуем посты в JSON
    posts_json = [
        {
            "id": post.id,
            "user_id": post.user_id,
            "content": post.content,
            "distance": post.distance,
            "duration": post.duration,
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
        for post in unique_posts
    ]

    return JSONResponse(content=posts_json)


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

async def check():
    # Проверка и создание бакета, если он не существует
    bucket_name = "posts"
    if not minio_client.bucket_exists(bucket_name):
        minio_client.make_bucket(bucket_name)
        print(f"Bucket '{bucket_name}' created.")
    else:
        print(f"Bucket '{bucket_name}' already exists.")
async def upload_photo_to_minio(file: UploadFile, bucket_name: str):
    await check()
    try:
        # Генерируем уникальное имя файла
        file_name = f"{uuid.uuid4()}_{file.filename}"
        file_size = file.size

        # Загружаем файл в MinIO
        minio_client.put_object(
            bucket_name,
            file_name,
            file.file,
            length=file_size,
            content_type=file.content_type
        )

        # Возвращаем URL файла
        return f"http://localhost:9000/{bucket_name}/{file_name}"
    except S3Error as e:
        print(f"Error uploading file to MinIO: {e}")
        raise

@router.post("/posts_create", response_model=PostInDB)
async def create_post(
    post: str = Form(...),  # Принимаем PostCreate как JSON-строку
    photos: List[UploadFile] = File(...),  # Список загруженных файлов
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

    # Сохраняем загруженные фотографии в MinIO
    photo_urls = []
    for photo in photos:
        photo_url = await upload_photo_to_minio(photo, "posts")
        db_photo = PostPhoto(post_id=db_post.id, photo_url=photo_url)
        db.add(db_photo)
        photo_urls.append(photo_url)

    await db.commit()

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
        # Убираем лайк
        await db.delete(existing_like)
        post.likes_count -= 1
        liked = False
    else:
        # Добавляем лайк
        new_like = PostLike(user_id=current_user.id, post_id=post_id)
        db.add(new_like)
        post.likes_count += 1
        liked = True

    await db.commit()
    await db.refresh(post)

    # Отправляем обновление через WebSocket
    await broadcast_feed_update({
        "type": "like",
        "post_id": post_id,
        "likes_count": post.likes_count,
        "liked": liked,  # Отправляем состояние лайка для текущего пользователя
        "user_id": current_user.id  # Добавляем ID пользователя, который поставил лайк
    })

    await broadcast_post_update(post_id, {
        "type": "like",
        "post_id": post_id,
        "likes_count": post.likes_count,
        "liked": liked,
        "user_id": current_user.id
    })

    return {"likes_count": post.likes_count, "liked": liked}


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
        "comment": {
            "id": new_comment.id,
            "user_id": new_comment.user_id,
            "content": new_comment.content,
            "created_at": new_comment.created_at.isoformat(),
            "user": {
                "username": current_user.full_name  # Или current_user.username
            }
        }
    }

    # Отправляем комментарий через WebSocket
    await broadcast_feed_update(comment_data)
    await broadcast_post_update(post_id, comment_data)

    return comment_data["comment"]


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
                "avatar_url": comment.user.avatar_url  # Должно быть здесь
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
            "route_data": post.route_data,
            "likes_count": post.likes_count,
            "comments_count": post.comments_count,
            "created_at": post.created_at,
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
