from pydantic import BaseModel, Field, ConfigDict, model_validator
from datetime import datetime
from typing import Optional, List
from enum import Enum

from app.event.models_event import Event

# Pydantic модели
class EventType(str, Enum):
    RUNNING = "RUNNING"
    CYCLING = "CYCLING"
    HIKING = "HIKING"
    TRAINING = "TRAINING"

class ApprovedType(str, Enum):
    APPROVED = "APPROVED"
    AWAITS = "AWAITS"
    DENIED = "DENIED"

class RoutePoint(BaseModel):
    latitude: float = Field(..., description="Широта точки маршрута")
    longitude: float = Field(..., description="Долгота точки маршрута")
    timestamp: Optional[datetime] = Field(None, description="Временная метка точки")
    model_config = ConfigDict(from_attributes=True)

class EventCreate(BaseModel):
    title: str = Field(..., description="Название мероприятия")
    description: Optional[str] = Field(None, description="Описание мероприятия")
    event_type: EventType = Field(..., description="Тип мероприятия")
    goal: Optional[str] = Field(None, description="Цель мероприятия")
    start_time: Optional[datetime] = Field(None, description="Время начала")
    end_time: Optional[datetime] = Field(None, description="Время окончания")
    difficulty: str = Field(..., description="Уровень сложности (новичок, любитель, профессионал)")
    max_participants: int = Field(..., description="Максимальное количество участников")
    is_public: bool = Field(default=True, description="Открытое/закрытое мероприятие")
    route_data: List[RoutePoint] = Field(..., description="Точки маршрута в JSON-формате")
    create_group_chat: bool = Field(default=False, description="Флаг для создания группового чата")

class EventRead(BaseModel):
    id: int
    title: str
    description: Optional[str]
    event_type: EventType
    goal: Optional[str]
    start_time: Optional[datetime]
    end_time: Optional[datetime]
    difficulty: str
    max_participants: int
    is_public: bool
    organizer_id: int
    available_seats: int
    route_data: Optional[List[dict]] = None
    group_chat_id: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)

    @model_validator(mode='before')
    @classmethod
    def prepare_route_data(cls, data):
        """Преобразуем route_data для совместимости"""
        if isinstance(data, Event):
            # Для ORM-объектов
            data_dict = data.__dict__
            if 'route_data' in data_dict:
                data_dict['route_data'] = data.route_data
            return data_dict
        return data

class EventParticipantCreate(BaseModel):
    event_id: int = Field(..., description="ID мероприятия")
    user_id: int = Field(..., description="ID пользователя")
    approved: ApprovedType = Field(default=ApprovedType.AWAITS, description="Статус заявки")