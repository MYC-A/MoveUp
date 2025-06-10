#post/schemas_posts.py

from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List, Dict

class RoutePoint(BaseModel):
    latitude: float
    longitude: float
    timestamp: datetime
class UserInPost(BaseModel):
    id: int
    full_name: str
    avatar_url: Optional[str] = None
class PostBase(BaseModel):
    content: str
    distance: float
    duration: int
    route_data: List[RoutePoint]

class PostCreate(PostBase):
    likes_count: Optional[int] = 0  # Разрешить None и установить значение по умолчанию
    comments_count: Optional[int] = 0  # Разрешить None и установить значение по умолчанию



class PostInDB(PostBase):
    id: int
    user_id: int
    """ Исправить чтобы при создании поста были 0"""
    likes_count: Optional[int] = 0  # Разрешить None и установить значение по умолчанию
    comments_count: Optional[int] = 0  # Разрешить None и установить значение по умолчанию

    class Config:
        from_attributes = True

class PostInProfile(PostInDB):
    user: UserInPost
    created_at: datetime
    liked_by_current_user:bool
    photo_urls:List

