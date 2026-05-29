from pydantic import BaseModel, Field, ConfigDict, field_validator, model_validator
from datetime import datetime
from math import atan2, cos, radians, sin, sqrt
from typing import Optional, List
from enum import Enum

from app.event.models_event import Event
from app.event.cities import canonical_city

MAX_ROUTE_DISTANCE_KM = 200
EARTH_RADIUS_KM = 6371

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
    latitude: float = Field(..., ge=-90, le=90, description="Широта точки маршрута")
    longitude: float = Field(..., ge=-180, le=180, description="Долгота точки маршрута")
    timestamp: Optional[datetime] = Field(None, description="Временная метка точки")
    model_config = ConfigDict(from_attributes=True)

class EventCreate(BaseModel):
    title: str = Field(..., description="Название мероприятия")
    description: Optional[str] = Field(None, description="Описание мероприятия")
    event_type: EventType = Field(..., description="Тип мероприятия")
    goal: Optional[str] = Field(None, description="Цель мероприятия")
    city: Optional[str] = Field(None, description="Город мероприятия")
    start_time: Optional[datetime] = Field(None, description="Время начала")
    end_time: Optional[datetime] = Field(None, description="Время окончания")
    difficulty: str = Field(..., description="Уровень сложности (новичок, любитель, профессионал)")
    max_participants: int = Field(..., description="Максимальное количество участников")
    is_public: bool = Field(default=True, description="Открытое/закрытое мероприятие")
    route_data: List[RoutePoint] = Field(..., description="Точки маршрута в JSON-формате")
    create_group_chat: bool = Field(default=False, description="Флаг для создания группового чата")

    @field_validator("city")
    @classmethod
    def validate_city(cls, value):
        if value is None or not value.strip():
            return None

        city = canonical_city(value)
        if city is None:
            raise ValueError("Выберите город из списка")
        return city

    @field_validator("route_data")
    @classmethod
    def validate_route_distance(cls, value):
        if len(value) < 2:
            return value

        distance_km = _calculate_route_distance_km(value)
        if distance_km > MAX_ROUTE_DISTANCE_KM:
            raise ValueError(f"Маршрут не должен быть длиннее {MAX_ROUTE_DISTANCE_KM} км")
        return value

    @field_validator("max_participants")
    @classmethod
    def validate_max_participants(cls, value):
        if value < 1:
            raise ValueError("Количество участников должно быть не меньше 1")
        return value

    @model_validator(mode="after")
    def validate_time_range(self):
        if (
            self.start_time is not None
            and self.end_time is not None
            and self.end_time <= self.start_time
        ):
            raise ValueError("Время окончания должно быть позже времени начала")
        return self

class EventRead(BaseModel):
    id: int
    title: str
    description: Optional[str]
    event_type: EventType
    goal: Optional[str]
    city: Optional[str] = None
    start_time: Optional[datetime]
    end_time: Optional[datetime]
    difficulty: str
    max_participants: int
    is_public: bool
    organizer_id: int
    available_seats: int
    route_data: Optional[List[dict]] = None
    group_chat_id: Optional[int] = None
    organizer_name: Optional[str] = None
    participants_count: int = 0
    is_expired: bool = False

    model_config = ConfigDict(from_attributes=True)

    @model_validator(mode='before')
    @classmethod
    def prepare_route_data(cls, data):
        """Преобразуем route_data для совместимости"""
        if isinstance(data, Event):
            # Для ORM-объектов
            data_dict = {
                "id": data.id,
                "title": data.title,
                "description": data.description,
                "event_type": data.event_type,
                "goal": data.goal,
                "city": data.city,
                "start_time": data.start_time,
                "end_time": data.end_time,
                "difficulty": data.difficulty,
                "max_participants": data.max_participants,
                "is_public": data.is_public,
                "organizer_id": data.organizer_id,
                "available_seats": data.available_seats,
                "route_data": data.route_data,
                "group_chat_id": data.group_chat_id,
                "participants_count": max(data.max_participants - data.available_seats, 0),
                "is_expired": _is_event_expired(data.start_time, data.end_time),
            }

            organizer = data.__dict__.get("organizer")
            if organizer is not None:
                data_dict["organizer_name"] = organizer.full_name or organizer.username
            return data_dict
        return data

class EventParticipantCreate(BaseModel):
    event_id: int = Field(..., description="ID мероприятия")
    user_id: int = Field(..., description="ID пользователя")
    approved: ApprovedType = Field(default=ApprovedType.AWAITS, description="Статус заявки")


def _calculate_route_distance_km(points: List[RoutePoint]) -> float:
    total_distance = 0.0

    for index in range(len(points) - 1):
        start = points[index]
        end = points[index + 1]
        lat1 = radians(start.latitude)
        lon1 = radians(start.longitude)
        lat2 = radians(end.latitude)
        lon2 = radians(end.longitude)

        d_lat = lat2 - lat1
        d_lon = lon2 - lon1
        a = (
            sin(d_lat / 2) ** 2
            + cos(lat1) * cos(lat2) * sin(d_lon / 2) ** 2
        )
        a = min(1.0, max(0.0, a))
        c = 2 * atan2(sqrt(a), sqrt(1 - a))
        total_distance += EARTH_RADIUS_KM * c

    return total_distance


def _is_event_expired(start_time: Optional[datetime], end_time: Optional[datetime]) -> bool:
    event_finish = end_time or start_time
    if event_finish is None:
        return False
    now = datetime.utcnow()
    if event_finish.tzinfo is not None:
        now = datetime.now(event_finish.tzinfo)
    return event_finish < now
