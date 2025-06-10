from datetime import datetime

from pydantic import BaseModel, Field
from typing import List

# Схемы для личных сообщений
class MessageRead(BaseModel):
    id: int = Field(..., description="Уникальный идентификатор сообщения")
    sender_id: int = Field(..., description="ID отправителя сообщения")
    recipient_id: int = Field(..., description="ID получателя сообщения")
    content: str = Field(..., description="Содержимое сообщения")

class MessageCreate(BaseModel):
    recipient_id: int = Field(..., description="ID получателя сообщения")
    content: str = Field(..., description="Содержимое сообщения")

# Схемы для групповых чатов
class GroupChatCreate(BaseModel):
    name: str = Field(..., description="Название группового чата")
    participants: List[int] = Field(..., description="Список ID участников")

class GroupMessageRead(BaseModel):
    id: int = Field(..., description="Уникальный идентификатор сообщения")
    group_chat_id: int = Field(..., description="ID группового чата")
    sender_id: int = Field(..., description="ID отправителя сообщения")
    sender_name: str = Field(..., description="Имя отправителя")
    content: str = Field(..., description="Содержимое сообщения")
    is_read: bool = Field(..., description="Прочитано ли сообщение текущим пользователем")
    created_at: datetime = Field(..., description="Время создания сообщения")

class GroupMessageCreate(BaseModel):
    group_chat_id: int = Field(..., description="ID группового чата")
    content: str = Field(..., description="Содержимое сообщения")


class MarkReadRequest(BaseModel):
    recipient_id: int
