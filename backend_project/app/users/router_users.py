from typing import List
import logging
import random
from datetime import datetime, timedelta

from fastapi import APIRouter, Response, HTTPException, Depends, status
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from jose import jwt, JWTError
from app.core.config import get_auth_data
from app.core.rate_limit import (
    login_rate_limiter, register_rate_limiter, verify_rate_limiter,
    resend_rate_limiter,
)
from app.db.base import get_db
from app.email.service import EmailService
from app.exceptions import UserAlreadyExistsException, IncorrectEmailOrPasswordException, PasswordMismatchException
from app.users.auth_users import (
    get_password_hash, authenticate_user, create_access_token,
    create_refresh_token, verify_password,
)
from app.users.dao_users import UsersDAO
from app.users.models_user import User
from app.users.dependensies_user import get_current_user_id
from app.users.schemas_user import (
    UserRegister, UserAuth, UserRead, EmailVerify, EmailResend, PasswordChange,
    RefreshRequest,
)
from fastapi.templating import Jinja2Templates # Для работы с шаблонами HTML


router = APIRouter(prefix='/auth', tags=['Auth'])

templates = Jinja2Templates(directory='app/templates')

CODE_TTL_MINUTES = 30


def _generate_code() -> str:
    return f"{random.randint(0, 999999):06d}"

@router.get("/users", response_model=List[UserRead])
async def get_users():
    users_all = await UsersDAO.find_all()
    # Используем генераторное выражение для создания списка
    for user in users_all:
        print(f"id:{user.id}, full_name {user.full_name}")
    return [{'id': user.id, 'full_name': user.full_name} for user in users_all]

@router.get("/", response_class=HTMLResponse, summary="Страница авторизации")
async def get_categories(request: Request):
    return templates.TemplateResponse("auth.html", {"request": request})

def _issue_tokens(response: Response, user_id: int) -> dict:
    """Выдаёт пару access+refresh и кладёт access в httponly-cookie."""
    access_token = create_access_token({"sub": str(user_id)})
    refresh_token = create_refresh_token({"sub": str(user_id)})
    response.set_cookie(key="users_access_token", value=access_token, httponly=True)
    return {"access_token": access_token, "refresh_token": refresh_token}


@router.post("/register/")
async def register_user(
    user_data: UserRegister,
    _: None = Depends(register_rate_limiter),
) -> dict:
    user = await UsersDAO.find_one_or_none(email=user_data.email)
    if user:
        raise UserAlreadyExistsException

    if user_data.password != user_data.password_check:
        raise PasswordMismatchException

    code = _generate_code()
    hashed_password = get_password_hash(user_data.password)
    await UsersDAO.add(
        full_name=user_data.full_name,
        email=user_data.email,
        hashed_password=hashed_password,
        city=user_data.city,
        weight=user_data.weight,
        height=user_data.height,
        is_verified=False,
        # Код подтверждения храним хэшированным (как пароль).
        verification_code=get_password_hash(code),
        verification_code_expires=datetime.utcnow() + timedelta(minutes=CODE_TTL_MINUTES),
    )

    await EmailService.send_verification_code(user_data.email, code)

    return {
        'message': 'Код подтверждения отправлен на email.',
        'requires_verification': True,
        'email': user_data.email,
    }


@router.post("/verify_email/")
async def verify_email(
    response: Response,
    data: EmailVerify,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(verify_rate_limiter),
):
    result = await db.execute(select(User).filter(User.email == data.email))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")

    if user.is_verified:
        tokens = _issue_tokens(response, user.id)
        return {'ok': True, **tokens, 'message': 'Email уже подтверждён'}

    if (not user.verification_code
            or not verify_password(data.code, user.verification_code)):
        raise HTTPException(status_code=400, detail="Неверный код подтверждения")
    if user.verification_code_expires and user.verification_code_expires < datetime.utcnow():
        raise HTTPException(status_code=400, detail="Код подтверждения истёк. Запросите новый.")

    user.is_verified = True
    user.verification_code = None
    user.verification_code_expires = None
    await db.commit()

    # Автоматически авторизуем — чтобы после подтверждения сразу войти.
    tokens = _issue_tokens(response, user.id)
    return {'ok': True, **tokens, 'message': 'Email подтверждён!'}


@router.post("/resend_code/")
async def resend_code(
    data: EmailResend,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(resend_rate_limiter),
):
    result = await db.execute(select(User).filter(User.email == data.email))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if user.is_verified:
        return {'message': 'Email уже подтверждён'}

    code = _generate_code()
    user.verification_code = get_password_hash(code)
    user.verification_code_expires = datetime.utcnow() + timedelta(minutes=CODE_TTL_MINUTES)
    await db.commit()
    await EmailService.send_verification_code(data.email, code)
    return {'message': 'Новый код подтверждения отправлен.'}


@router.post("/login/")
async def auth_user(
    response: Response,
    user_data: UserAuth,
    _: None = Depends(login_rate_limiter),
):
    check = await authenticate_user(email=user_data.email, password=user_data.password)
    if check is None:
        raise IncorrectEmailOrPasswordException
    if not check.is_verified:
        # Особый код, чтобы клиент увёл на экран подтверждения.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="EMAIL_NOT_VERIFIED",
        )
    tokens = _issue_tokens(response, check.id)
    return {'ok': True, **tokens, 'message': 'Авторизация успешна!'}


@router.post("/refresh/")
async def refresh_tokens(response: Response, data: RefreshRequest):
    """Обновление пары токенов по refresh-токену (с ротацией)."""
    try:
        auth = get_auth_data()
        payload = jwt.decode(
            data.refresh_token, auth['secret_key'], algorithms=[auth['algorithm']]
        )
    except JWTError:
        raise HTTPException(status_code=401, detail="Невалидный refresh-токен")

    if payload.get('type') != 'refresh':
        raise HTTPException(status_code=401, detail="Невалидный refresh-токен")
    user_id = payload.get('sub')
    if not user_id:
        raise HTTPException(status_code=401, detail="Невалидный refresh-токен")

    user = await UsersDAO.find_one_or_none_by_id(int(user_id))
    if not user:
        raise HTTPException(status_code=401, detail="Пользователь не найден")

    tokens = _issue_tokens(response, user.id)
    return {'ok': True, **tokens}


@router.post("/change_password/")
async def change_password(
    data: PasswordChange,
    user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).filter(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if not verify_password(data.old_password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Текущий пароль неверный")
    user.hashed_password = get_password_hash(data.new_password)
    await db.commit()
    return {'message': 'Пароль изменён'}


@router.post("/logout/")
async def logout_user(response: Response):
    response.delete_cookie(key="users_access_token")
    return {'message': 'Пользователь успешно вышел из системы'}

@router.get("/current_user")
async def get_current_user(user_id: int = Depends(get_current_user_id)):
    return user_id