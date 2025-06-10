from sqlalchemy import Column, Integer, String, DateTime, Float, ForeignKey, Boolean, Enum, JSON
from sqlalchemy.orm import relationship
from app.db.base import Base
from datetime import datetime
from enum import Enum as PyEnum

# Используем стандартный Python Enum для типов мероприятий
class EventType(PyEnum):
    RUNNING = "RUNNING"
    CYCLING = "CYCLING"
    HIKING = "HIKING"
    TRAINING = "TRAINING"

class ApprovedType(PyEnum):
    APPROVED = "APPROVED"
    AWAITS = "AWAITS"
    DENIED = "DENIED"


class Event(Base):
    __tablename__ = "events"
    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    event_type = Column(Enum(EventType), nullable=False)
    goal = Column(String, nullable=True)
    start_time = Column(DateTime, nullable=True)
    end_time = Column(DateTime, nullable=True)
    difficulty = Column(String, nullable=False)
    max_participants = Column(Integer, nullable=False)
    is_public = Column(Boolean, default=True)
    organizer_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    available_seats = Column(Integer, nullable=False)
    group_chat_id = Column(Integer, ForeignKey("group_chats.id"), nullable=True)
    route_data = Column(JSON, nullable=True)  # JSON-поле для маршрута

    organizer = relationship("User", back_populates="organized_events")
    participants = relationship("EventParticipant", back_populates="event", lazy="selectin")

    @property
    def start_location(self):
        """Возвращает первую точку маршрута"""
        if self.route_data and len(self.route_data) > 0:
            return {
                "latitude": self.route_data[0]["latitude"],
                "longitude": self.route_data[0]["longitude"]
            }
        return None

    @property
    def end_location(self):
        """Возвращает последнюю точку маршрута"""
        if self.route_data and len(self.route_data) > 0:
            return {
                "latitude": self.route_data[-1]["latitude"],
                "longitude": self.route_data[-1]["longitude"]
            }
        return None
"""
class RoutePoint(Base):
    __tablename__ = "route_points"
    id = Column(Integer, primary_key=True, autoincrement=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False)  # Связь с мероприятием
    latitude = Column(Float, nullable=False)  # Широта
    longitude = Column(Float, nullable=False)  # Долгота
    name = Column(String, nullable=True)  # Название точки (опционально)
    timestamp = Column(DateTime, nullable=False)  # Временная метка
    event = relationship("Event", back_populates="route_points")  # Связь с мероприятием
"""

class EventParticipant(Base):
    __tablename__ = "event_participants"
    id = Column(Integer, primary_key=True, autoincrement=True)
    event_id = Column(Integer, ForeignKey("events.id"), nullable=False)  # Связь с мероприятием
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)  # Связь с пользователем
    approved = Column(Enum(ApprovedType), nullable=False) # Статус заявки
    user = relationship("User", back_populates="events_participated")
    event = relationship("Event", back_populates="participants")
    is_new = Column(Boolean, default=True)  # Флаг для новых заявок
    status_changed = Column(Boolean, default=False)  # Флаг для изменений статуса
