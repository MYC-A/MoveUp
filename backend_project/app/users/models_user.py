# user/models_user.py
from sqlalchemy import Column, String, DateTime, Boolean, Integer
from sqlalchemy.orm import relationship
from app.db.base import Base
import uuid
from datetime import datetime
from app.posts.models_posts import Post
from app.models.follow import UserFollow


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String, unique=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    full_name = Column(String)
    bio = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    total_subscribers = Column(Integer,default=0)
    total_subscriptions = Column(Integer,default=0)

    posts = relationship("Post", back_populates="user")
    comments = relationship("Comment", back_populates="user")  # Добавлено
    organized_events = relationship("Event", back_populates="organizer")
    events_participated = relationship("EventParticipant", back_populates="user")

    followers = relationship(
        "UserFollow",
        foreign_keys="UserFollow.following_id",
        back_populates="following"
    )
    following = relationship(
        "UserFollow",
        foreign_keys="UserFollow.follower_id",
        back_populates="follower"
    )


