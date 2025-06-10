# app/posts/models_posts.py
from sqlalchemy import Column, String, DateTime, ForeignKey, Float, Integer, JSON
from sqlalchemy.orm import relationship
from app.db.base import Base
import uuid
from datetime import datetime
from .models_posts_like import PostLike
from .models_posts_comments import Comment

class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    content = Column(String) # Текст поста
    distance = Column(Float)
    duration = Column(Integer)  # in seconds
    route_data = Column(JSON) # Данные маршрута (список точек)
    likes_count = Column(Integer, default=0)
    comments_count = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="posts")
    likes = relationship("PostLike", back_populates="post")
    comments = relationship("Comment", back_populates="post")
    photos = relationship("PostPhoto", back_populates="post")  # Добавлено


class PostPhoto(Base):
    __tablename__ = "post_photos"

    id = Column(Integer, primary_key=True, autoincrement=True)
    post_id = Column(Integer, ForeignKey("posts.id"))
    photo_url = Column(String)  # Ссылка на фотографию в хранилище

    post = relationship("Post", back_populates="photos")