from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Request, Depends, Query, BackgroundTasks, HTTPException
from fastapi import Body
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from typing import List, Dict, Optional

from sqlalchemy.dialects.postgresql import insert

from jose import jwt, JWTError
from app.core.config import get_auth_data
from app.chat.dao import MessagesDAO, GroupMessagesDAO
from app.chat.models import GroupMessageReadStatus
from app.chat.schemas import MessageRead, MessageCreate, GroupChatCreate, GroupMessageCreate, GroupMessageRead, \
    MarkReadRequest
from app.db.base import async_session_maker
from app.push.service import PushNotificationService
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
                "avatar_url": user_data.avatar_url,
            },
            "users_with_messages": [
                {
                    "id": user.id,
                    "full_name": user.full_name,
                    "avatar_url": user.avatar_url,
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
                "avatar_url": user_data.avatar_url,
            },
            "users_with_messages": [
                {
                    "id": user.id,
                    "full_name": user.full_name,
                    "avatar_url": user.avatar_url,
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
# Активные WebSocket-подключения: {user_id: [websocket, ...]}
# Список позволяет одному пользователю держать несколько соединений одновременно
# (например, ChatListScreen + ChatScreen на одном устройстве).
active_connections: Dict[int, List[WebSocket]] = {}


def _truncate_push_body(content: str, max_length: int = 120) -> str:
    normalized = " ".join(content.split())
    if len(normalized) <= max_length:
        return normalized
    return f"{normalized[:max_length - 1]}..."


def _count_unread_total(unread: Dict[str, Dict[int, int]]) -> int:
    total = 0
    for counters in unread.values():
        total += sum(counters.values())
    return total


def _as_utc(value: Optional[datetime]) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _personal_message_response(message) -> dict:
    return {
        "id": message.id,
        "sender_id": message.sender_id,
        "recipient_id": message.recipient_id,
        "content": message.content,
        "is_read": message.is_read,
        "created_at": _as_utc(message.created_at),
    }


async def _send_personal_message_push(
    recipient_id: int,
    sender: User,
    message_id: int,
    content: str,
) -> None:
    if not PushNotificationService.is_enabled():
        return

    unread = await MessagesDAO.get_unread_messages_count(recipient_id)
    await PushNotificationService.send_chat_message_push(
        recipient_id=recipient_id,
        title=sender.full_name or "Новое сообщение",
        body=_truncate_push_body(content),
        data={
            "type": "chat_message",
            "conversation_type": "personal",
            "conversation_id": sender.id,
            "conversation_title": sender.full_name or "Пользователь",
            "sender_id": sender.id,
            "message_id": message_id,
        },
        unread_count=_count_unread_total(unread),
    )


async def _send_group_message_push(
    recipient_id: int,
    sender: User,
    group_chat_id: int,
    group_chat_name: str,
    message_id: int,
    content: str,
) -> None:
    if not PushNotificationService.is_enabled():
        return

    sender_name = sender.full_name or "Участник"
    unread = await MessagesDAO.get_unread_messages_count(recipient_id)
    await PushNotificationService.send_chat_message_push(
        recipient_id=recipient_id,
        title=group_chat_name,
        body=f"{sender_name}: {_truncate_push_body(content)}",
        data={
            "type": "chat_message",
            "conversation_type": "group",
            "conversation_id": group_chat_id,
            "conversation_title": group_chat_name,
            "group_chat_id": group_chat_id,
            "sender_id": sender.id,
            "message_id": message_id,
        },
        unread_count=_count_unread_total(unread),
    )

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
    Уведомляет отправителя через WebSocket, чтобы он видел двойную галочку (✓✓) в реальном времени.
    """
    marked_count = await MessagesDAO.mark_messages_as_read(current_user.id, data.recipient_id)
    if marked_count > 0:
        await notify_user(data.recipient_id, {
            'type': 'read_receipt',
            'reader_id': current_user.id,
        })
    return {"status": "ok", "msg": "Messages marked as read", "marked_count": marked_count}


# Функция для отправки сообщения пользователю, если он подключен
async def notify_user(user_id: int, message: dict):
    connections = active_connections.get(user_id)
    if not connections:
        return
    dead: List[WebSocket] = []
    for ws in list(connections):
        try:
            await ws.send_json(message)
        except Exception:
            dead.append(ws)
    for ws in dead:
        try:
            connections.remove(ws)
        except ValueError:
            pass


# WebSocket эндпоинт для соединений
def _user_id_from_token(token: Optional[str]) -> Optional[int]:
    """Достаёт id пользователя из JWT (для аутентификации WebSocket)."""
    if not token:
        return None
    try:
        auth = get_auth_data()
        payload = jwt.decode(token, auth['secret_key'], algorithms=[auth['algorithm']])
        sub = payload.get('sub')
        return int(sub) if sub else None
    except (JWTError, ValueError, TypeError):
        return None


@router.websocket("/ws/{user_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    user_id: int,
    token: Optional[str] = Query(None),
):
    # Аутентификация: user_id берём из токена и сверяем с путём, иначе
    # любой мог бы подключиться как чужой пользователь и читать его уведомления.
    auth_user_id = _user_id_from_token(token)
    if auth_user_id is None or auth_user_id != user_id:
        await websocket.close(code=4401)
        return

    # Принимаем WebSocket-соединение
    await websocket.accept()
    if user_id not in active_connections:
        active_connections[user_id] = []
    active_connections[user_id].append(websocket)
    try:
        while True:
            try:
                await websocket.receive_json()
                await asyncio.sleep(1)
            except Exception:
                break
    except WebSocketDisconnect:
        pass
    finally:
        conns = active_connections.get(user_id)
        if conns is not None:
            try:
                conns.remove(websocket)
            except ValueError:
                pass


# Получение сообщений между двумя пользователями
@router.get("/messages/{user_id}", response_model=List[MessageRead])
async def get_messages(
    user_id: int,
    limit: int = Query(30, ge=1, le=100),
    before_id: Optional[int] = Query(None, ge=1),
    current_user: User = Depends(get_current_user),
):
    # Возвращаем последнюю страницу сообщений между текущим пользователем и другим пользователем.
    messages = await MessagesDAO.get_messages_between_users(
        user_id_1=user_id,
        user_id_2=current_user.id,
        limit=limit,
        before_id=before_id,
    ) or []
    return [_personal_message_response(message) for message in messages]
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
@router.post("/messages", response_model=MessageRead)
async def send_message(
    message: MessageCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    saved_message = await MessagesDAO.add(
        sender_id=current_user.id,
        content=message.content,
        recipient_id=message.recipient_id
    )
    message_data = {
        'id': saved_message.id,
        'type': 'personal',
        'sender_id': current_user.id,
        'recipient_id': message.recipient_id,
        'content': message.content,
        'is_read': False,
        'created_at': _as_utc(saved_message.created_at).isoformat(),
    }
    await notify_user(message.recipient_id, message_data)
    background_tasks.add_task(
        _send_personal_message_push,
        recipient_id=message.recipient_id,
        sender=current_user,
        message_id=saved_message.id,
        content=message.content,
    )
    return _personal_message_response(saved_message)

# Эндпоинт для отправки сообщения в групповой чат

@router.post("/group_chats/messages")
async def send_group_message(
    message: GroupMessageCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    # Только участник чата может писать в него (иначе — инъекция в чужой чат).
    if not await GroupMessagesDAO.is_participant(message.group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")

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

    group_chat_name = await GroupMessagesDAO.get_group_chat_name(message.group_chat_id)
    group_chat_name = group_chat_name or "Групповой чат"

    # Отправляем realtime-уведомления всем участникам и push получателям.
    for participant_id in participants:
        is_read = participant_id == current_user.id
        message_data = {
            'id': group_message.id,
            'type': 'group',
            'group_chat_id': group_message.group_chat_id,
            'sender_id': group_message.sender_id,
            'content': group_message.content,
            'sender_name': current_user.full_name,
            'created_at': _as_utc(group_message.created_at).isoformat(),
            'is_read': is_read
        }
        await notify_user(participant_id, message_data)
        if participant_id != current_user.id:
            background_tasks.add_task(
                _send_group_message_push,
                recipient_id=participant_id,
                sender=current_user,
                group_chat_id=group_message.group_chat_id,
                group_chat_name=group_chat_name,
                message_id=group_message.id,
                content=group_message.content,
            )

    return message_data

@router.delete("/messages/{message_id}")
async def delete_personal_message(
    message_id: int,
    current_user: User = Depends(get_current_user),
):
    """Удаление личного сообщения. Только отправитель может удалить.
    После удаления уведомляет обоих участников через WebSocket, чтобы
    сообщение исчезло с экрана собеседника в реальном времени."""
    message = await MessagesDAO.get_by_id(message_id)
    if message is None:
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    if message.sender_id != current_user.id:
        raise HTTPException(status_code=403, detail="Нет прав на удаление этого сообщения")

    recipient_id = message.recipient_id
    sender_id = message.sender_id
    await MessagesDAO.delete_message(message_id)

    deletion_event = {
        'type': 'message_deleted',
        'message_id': message_id,
        'conversation_type': 'personal',
    }
    await notify_user(recipient_id, deletion_event)
    await notify_user(sender_id, deletion_event)
    return {"status": "ok"}


@router.delete("/group_chats/{group_chat_id}/messages/{message_id}")
async def delete_group_message_endpoint(
    group_chat_id: int,
    message_id: int,
    current_user: User = Depends(get_current_user),
):
    """Удаление сообщения из группового чата. Только отправитель может удалить.
    После удаления уведомляет всех участников через WebSocket."""
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")
    message = await GroupMessagesDAO.get_message_by_id(message_id)
    if message is None:
        raise HTTPException(status_code=404, detail="Сообщение не найдено")
    if message.sender_id != current_user.id:
        raise HTTPException(status_code=403, detail="Нет прав на удаление этого сообщения")
    await GroupMessagesDAO.delete_message(message_id)

    participants = list(set(await GroupMessagesDAO.get_group_chat_participants(group_chat_id)))
    deletion_event = {
        'type': 'message_deleted',
        'message_id': message_id,
        'conversation_type': 'group',
        'group_chat_id': group_chat_id,
    }
    for participant_id in participants:
        await notify_user(participant_id, deletion_event)
    return {"status": "ok"}


@router.get("/group_chats/{group_chat_id}/get_messages", response_model=List[GroupMessageRead])
async def get_group_messages(
    group_chat_id: int,
    limit: int = Query(30, ge=1, le=100),
    before_id: Optional[int] = Query(None, ge=1),
    current_user: User = Depends(get_current_user),
):
    """
    Возвращает страницу сообщений из группового чата.
    """
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")
    return await GroupMessagesDAO.get_group_messages(
        group_chat_id,
        current_user.id,
        limit=limit,
        before_id=before_id,
    )

@router.post("/group_chats/{group_chat_id}/mark_as_read")
async def mark_group_messages_as_read(
    group_chat_id: int,
    current_user: User = Depends(get_current_user),
):
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")
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
    # Добавлять новых участников может только тот, кто сам состоит в чате.
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")
    # Не создаём дубликат, если пользователь уже в чате.
    if await GroupMessagesDAO.is_participant(group_chat_id, request.user_id):
        return {"status": "ok", "msg": "Participant already in group chat"}
    await GroupMessagesDAO.add_participant_to_group_chat(group_chat_id, request.user_id)
    return {"status": "ok", "msg": "Participant added to group chat"}


@router.post("/group_chats/{group_chat_id}/leave")
async def leave_group_chat(
    group_chat_id: int,
    current_user: User = Depends(get_current_user),
):
    """Текущий пользователь покидает групповой чат."""
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=404, detail="Вы не участник этого чата")
    await GroupMessagesDAO.remove_participant_from_group_chat(
        group_chat_id, current_user.id
    )
    return {"status": "ok", "msg": "Left group chat"}


@router.get("/group_chats/{group_chat_id}/participants")
async def get_group_chat_participants(
    group_chat_id: int,
    current_user: User = Depends(get_current_user),
):
    """Список участников группового чата (имя + аватар). Только для участников."""
    if not await GroupMessagesDAO.is_participant(group_chat_id, current_user.id):
        raise HTTPException(status_code=403, detail="Вы не участник этого чата")
    return await GroupMessagesDAO.get_group_chat_participant_details(group_chat_id)
