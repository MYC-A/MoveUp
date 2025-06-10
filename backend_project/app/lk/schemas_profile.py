from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import Optional, List
from enum import Enum
#pydantic модели
class EventResponse(BaseModel):
    id: int
    title: str
    description: str
    start_time: datetime  # Используем datetime вместо строки
    end_time: datetime  # Используем datetime вместо строки    # Используем строку вместо datetime

class EventsResponseAll(BaseModel):
    events: List[EventResponse]