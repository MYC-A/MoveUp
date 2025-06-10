# routes_friends.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session
from app.db.base import get_db  # Функция для получения сессии базы данных
from app.models.follow import UserFollow  # Модель UserFollow
from app.users.dependensies_user import get_current_user, \
    get_current_user_id  # Функция для получения текущего пользователя
from app.users.models_user import User

router = APIRouter(prefix="/friends", tags=["Friends"])

@router.post("/follow/{user_id}")
async def follow_user(
    user_id: int,
    current_user: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Подписаться на пользователя"""
    if user_id == current_user:
        raise HTTPException(status_code=400, detail="Нельзя подписаться на себя")

    # Проверяем, существует ли уже подписка
    existing_follow = await db.execute(
        select(UserFollow).where(
            (UserFollow.follower_id == current_user) &
            (UserFollow.following_id == user_id)
        )
    )
    existing_follow = existing_follow.scalar_one_or_none()
    if existing_follow:
        raise HTTPException(status_code=400, detail="Вы уже подписаны на этого пользователя")

    # Проверяем, существует ли пользователь, на которого подписываемся
    followed_user = await db.execute(select(User).filter(User.id == user_id))
    followed_user = followed_user.scalars().first()
    if not followed_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Проверяем текущего пользователя
    current_user_data = await db.execute(select(User).filter(User.id == current_user))
    current_user_data = current_user_data.scalars().first()
    if not current_user_data:
        raise HTTPException(status_code=404, detail="Текущий пользователь не найден")

    # Создаем новую подписку
    follow = UserFollow(follower_id=current_user, following_id=user_id)
    db.add(follow)

    # Обновляем total_subscribers для пользователя, на которого подписались
    followed_user.total_subscribers = (followed_user.total_subscribers or 0) + 1

    # Обновляем total_subscriptions для текущего пользователя
    current_user_data.total_subscriptions = (current_user_data.total_subscriptions or 0) + 1

    await db.commit()
    return {"message": "Вы успешно подписались на пользователя"}

@router.delete("/unfollow/{user_id}")
async def unfollow_user(
    user_id: int,
    current_user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Отписаться от пользователя"""
    # Проверяем, существует ли подписка
    result = await db.execute(
        select(UserFollow).where(
            (UserFollow.follower_id == current_user_id) &
            (UserFollow.following_id == user_id)
        )
    )
    follow = result.scalars().first()
    if not follow:
        raise HTTPException(status_code=404, detail="Подписка не найдена")

    # Проверяем пользователя, от которого отписываемся
    followed_user = await db.execute(select(User).filter(User.id == user_id))
    followed_user = followed_user.scalars().first()
    if not followed_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    # Проверяем текущего пользователя
    current_user_data = await db.execute(select(User).filter(User.id == current_user_id))
    current_user_data = current_user_data.scalars().first()
    if not current_user_data:
        raise HTTPException(status_code=404, detail="Текущий пользователь не найден")

    # Уменьшаем total_subscribers для пользователя, от которого отписались
    if followed_user.total_subscribers:
        followed_user.total_subscribers = max(0, followed_user.total_subscribers - 1)

    # Уменьшаем total_subscriptions для текущего пользователя
    if current_user_data.total_subscriptions:
        current_user_data.total_subscriptions = max(0, current_user_data.total_subscriptions - 1)

    # Удаляем подписку
    await db.delete(follow)
    await db.commit()

    return {"message": "Вы успешно отписались от пользователя"}


@router.get("/is_following/{user_id}")
async def is_following(
    user_id: int,
    current_user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    existing_follow = await db.execute(
        select(UserFollow).where(
            (UserFollow.follower_id == current_user_id) &
            (UserFollow.following_id == user_id)
        )
    )
    existing_follow = existing_follow.scalar_one_or_none()
    return {"is_following": existing_follow is not None}