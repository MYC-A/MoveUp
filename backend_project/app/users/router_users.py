from typing import List
import logging

from fastapi import APIRouter, Response, HTTPException, Depends
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
from app.exceptions import UserAlreadyExistsException, IncorrectEmailOrPasswordException, PasswordMismatchException
from app.users.auth_users import get_password_hash, authenticate_user, create_access_token
from app.users.dao_users import UsersDAO
from app.users.dependensies_user import get_current_user_id
from app.users.schemas_user import UserRegister, UserAuth, UserRead
from fastapi.templating import Jinja2Templates # Для работы с шаблонами HTML


router = APIRouter(prefix='/auth', tags=['Auth'])

templates = Jinja2Templates(directory='app/templates')

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

@router.post("/register/")
async def register_user(user_data: UserRegister) -> dict:
    logging.info("НАЧАЛО" + str(user_data.dict()))
    user = await UsersDAO.find_one_or_none(email=user_data.email)
    print(user)
    if user:
        raise UserAlreadyExistsException

    if user_data.password != user_data.password_check:
        raise PasswordMismatchException("Пароли не совпадают")
    hashed_password = get_password_hash(user_data.password)
    await UsersDAO.add(
        full_name=user_data.full_name,
        email=user_data.email,
        hashed_password=hashed_password
    )

    return {'message': 'Вы успешно зарегистрированы!'}


@router.post("/login/")
async def auth_user(response: Response, user_data: UserAuth):
    check = await authenticate_user(email=user_data.email, password=user_data.password)
    if check is None:
        raise IncorrectEmailOrPasswordException
    access_token = create_access_token({"sub": str(check.id)})
    response.set_cookie(key="users_access_token", value=access_token, httponly=True)
    return {'ok': True, 'access_token': access_token, 'refresh_token': None, 'message': 'Авторизация успешна!'}


@router.post("/logout/")
async def logout_user(response: Response):
    response.delete_cookie(key="users_access_token")
    return {'message': 'Пользователь успешно вышел из системы'}

@router.get("/current_user")
async def get_current_user(user_id: int = Depends(get_current_user_id)):
    return user_id