from datetime import datetime

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Request, Depends, Query
from fastapi import Body
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from typing import List, Dict

from sqlalchemy.dialects.postgresql import insert

from app.chat.dao import MessagesDAO, GroupMessagesDAO
from app.chat.models import GroupMessageReadStatus
from app.chat.schemas import MessageRead, MessageCreate, GroupChatCreate, GroupMessageCreate, GroupMessageRead, \
    MarkReadRequest
from app.db.base import async_session_maker
from app.users.dao_users import UsersDAO
from app.users.dependensies_user import get_current_user
from app.users.models_user import User
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
import logging

# Создаем экземпляр маршрутизатора с префиксом /chat и тегом "Chat"
router = APIRouter(prefix='/chat', tags=['Chat'])
# Настройка шаблонов Jinja2
templates = Jinja2Templates(directory='app/templates')

templates.env.autoescape = False
templates.env.auto_reload = True


@router.get("/")
async def get_chat_page(
    request: Request,
    user_data: User = Depends(get_current_user),
    format: str = Query("html", description="Формат ответа: html или json")
):
    users_with_messages = await MessagesDAO.get_users_with_messages(user_data.id)
    group_chats = await GroupMessagesDAO.get_user_group_chats(user_data.id)

    if format == "json":
        return {
            "user": {
                "id": user_data.id,
                "full_name": user_data.full_name,
            },
            "users_with_messages": [
                {
                    "id": user.id,
                    "full_name": user.full_name,
                }
                for user in users_with_messages
                if user.id != user_data.id
            ],
            "group_chats": [
                {
                    "id": group_chat.id,
                    "name": group_chat.name,
                }
                for group_chat in group_chats
            ],
        }

    # Возвращаем HTML с данными в структуре, похожей на JSON
    print("Передаю в шаблон group_chats:", group_chats)

    return templates.TemplateResponse(
        "chat.html",
        {
            "request": request,
            "user": {
                "id": user_data.id,
                "full_name": user_data.full_name,
            },
            "users_with_messages": [
                {
                    "id": user.id,
                    "full_name": user.full_name,
                }
                for user in users_with_messages
                if user.id != user_data.id
            ],
            "group_chats": [
                {
                    "id": group_chat.id,
                    "name": group_chat.name,
                }
                for group_chat in group_chats
            ],
        },
    headers={"Cache-Control": "no-cache, no-store, must-revalidate"}

    )
# Активные WebSocket-подключения: {user_id: websocket}
active_connections: Dict[int, WebSocket] = {}

@router.get("/unread_messages_count", response_model=Dict[str, Dict[int, int]])
async def get_unread_messages_count(current_user: User = Depends(get_current_user)):
    """
    Возвращает количество непрочитанных сообщений для личных и групповых чатов.
    """
    unread_messages = await MessagesDAO.get_unread_messages_count(current_user.id)
    print(f"Непрочитанные сообщения: {unread_messages}")
    return unread_messages


@router.post("/mark_as_read")
async def mark_messages_as_read(
    data: MarkReadRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Помечает все непрочитанные сообщения между текущим пользователем и собеседником как прочитанные.
    """
    marked_count = await MessagesDAO.mark_messages_as_read(current_user.id, data.recipient_id)
    return {"status": "ok", "msg": "Messages marked as read", "marked_count": marked_count}


# Функция для отправки сообщения пользователю, если он подключен
async def notify_user(user_id: int, message: dict):
    #Отправить сообщение пользователю, если он подключен.
    if user_id in active_connections:
        websocket = active_connections[user_id]
        print(f"Уведомление пользователя {user_id}: {message}")
        # Отправляем сообщение в формате JSON
        await websocket.send_json(message)
    else:
        print(f"Пользователь {user_id} не подключен")


# WebSocket эндпоинт для соединений
@router.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: int):
    # Принимаем WebSocket-соединение
    await websocket.accept()
    # Сохраняем активное соединение для пользователя
    active_connections[user_id] = websocket
    try:
        while True:
            try:
                message = await websocket.receive_json()
                print(f"Получено сообщение от клиента: {message}")
                # Обработка сообщения или логика передачи
                # Просто поддерживаем соединение активным (1 секунда паузы)
                await asyncio.sleep(1)
            except Exception as e:
                print(f"Ошибка при обработке сообщения: {e}")
                break
    except WebSocketDisconnect:
        # Удаляем пользователя из активных соединений при отключении
        active_connections.pop(user_id, None)
    finally:
        # Удаляем соединение из активных
        active_connections.pop(user_id, None)
        print(f"Соединение для пользователя {user_id} закрыто")


# Получение сообщений между двумя пользователями
@router.get("/messages/{user_id}", response_model=List[MessageRead])
async def get_messages(user_id: int, current_user: User = Depends(get_current_user)):
    # Возвращаем список сообщений между текущим пользователем и другим пользователем
    return await MessagesDAO.get_messages_between_users(user_id_1=user_id, user_id_2=current_user.id) or []
@router.get("/users_with_messages", response_model=List[int])
async def get_users_with_messages(current_user: User = Depends(get_current_user)):
    """
    Возвращает список пользователей, с которыми у текущего пользователя есть переписка.
    """
    return await MessagesDAO.get_users_with_messages(current_user.id)

@router.get("/users_with_messages_pc", response_model=List[int])
async def get_users_with_messages(current_user: User = Depends(get_current_user)):
    """
    Возвращает список идентификаторов пользователей, с которыми у текущего пользователя есть переписка.
    """
    users = await MessagesDAO.get_users_with_messages(current_user.id)
    return [user.id for user in users]  # Возвращаем только список ID пользователей

# Эндпоинт для отправки личного сообщения
@router.post("/messages", response_model=MessageCreate)
async def send_message(message: MessageCreate, current_user: User = Depends(get_current_user)):
    await MessagesDAO.add(
        sender_id=current_user.id,
        content=message.content,
        recipient_id=message.recipient_id
    )
    message_data = {
        'type': 'personal',
        'sender_id': current_user.id,
        'recipient_id': message.recipient_id,
        'content': message.content,
        'is_read': False
    }
    await notify_user(message.recipient_id, message_data)
    return message

# Эндпоинт для отправки сообщения в групповой чат

@router.post("/group_chats/messages")
async def send_group_message(
    message: GroupMessageCreate,
    current_user: User = Depends(get_current_user),
):
    # Добавляем сообщение в групповой чат
    group_message = await GroupMessagesDAO.add_group_message(
        message.group_chat_id, current_user.id, message.content
    )

    # Получаем всех участников чата (удаляем дубликаты)
    participants = list(set(await GroupMessagesDAO.get_group_chat_participants(message.group_chat_id)))

    # Создаём записи в group_message_reads для всех участников
    async with async_session_maker() as session:
        values = [
            {
                "message_id": group_message.id,
                "user_id": participant_id,
                "read_at": datetime.utcnow() if participant_id == current_user.id else None,
                "group_chat_id": group_message.group_chat_id,
                "sender_id": group_message.sender_id,
                "sender_name": current_user.full_name,
                "content": group_message.content,
                "is_read": participant_id == current_user.id,
                "created_at": group_message.created_at
            }
            for participant_id in participants
        ]
        stmt = insert(GroupMessageReadStatus).values(values).on_conflict_do_nothing(
            index_elements=['message_id', 'user_id']
        )
        await session.execute(stmt)
        await session.commit()

    # Отправляем уведомления всем участникам
    for participant_id in participants:
        is_read = participant_id == current_user.id
        message_data = {
            'type': 'group',
            'group_chat_id': group_message.group_chat_id,
            'sender_id': group_message.sender_id,
            'content': group_message.content,
            'sender_name': current_user.full_name,
            'created_at': group_message.created_at.isoformat(),
            'is_read': is_read
        }
        await notify_user(participant_id, message_data)

    return message_data

@router.get("/group_chats/{group_chat_id}/get_messages", response_model=List[GroupMessageRead])
async def get_group_messages(
    group_chat_id: int,
    current_user: User = Depends(get_current_user),
):
    """
        Возвращает список сообщений из группового чата.
        """
    return await GroupMessagesDAO.get_group_messages(group_chat_id, current_user.id)

@router.post("/group_chats/{group_chat_id}/mark_as_read")
async def mark_group_messages_as_read(
    group_chat_id: int,
    current_user: User = Depends(get_current_user),
):
    marked_count = await GroupMessagesDAO.mark_group_messages_as_read(
        group_chat_id, current_user.id
    )
    return {"status": "ok", "marked": marked_count}



# Эндпоинт для создания группового чата
@router.post("/group_chats", response_model=Dict[str, int])
async def create_group_chat(group_chat: GroupChatCreate, current_user: User = Depends(get_current_user)):
    """
    Создает новый групповой чат.
    """
    group_chat_id = await GroupMessagesDAO.create_group_chat(group_chat.name, current_user.id, group_chat.participants)
    return {"group_chat_id": group_chat_id}

from pydantic import BaseModel

class AddParticipantRequest(BaseModel):
    user_id: int

@router.post("/group_chats/{group_chat_id}/add_participant")
async def add_participant_to_group_chat(
    group_chat_id: int,
    request: AddParticipantRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Добавляет участника в групповой чат.
    """
    await GroupMessagesDAO.add_participant_to_group_chat(group_chat_id, request.user_id)
    return {"status": "ok", "msg": "Participant added to group chat"}


