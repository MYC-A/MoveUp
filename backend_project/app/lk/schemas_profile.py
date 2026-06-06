from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import Optional, List
from enum import Enum
#pydantic модели
class EventResponse(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    city: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    max_participants: Optional[int] = None
    available_seats: Optional[int] = None
    participants_count: int = 0
    pending_applications_count: int = 0
    is_expired: bool = False

class EventsResponseAll(BaseModel):
    events: List[EventResponse]
