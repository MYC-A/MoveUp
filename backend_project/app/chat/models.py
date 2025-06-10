#chat/models_posts.py
from datetime import datetime

from sqlalchemy import Integer, Text, ForeignKey, Boolean, String, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base
from sqlalchemy import Table, Column


class Message(Base):
    __tablename__ = 'messages'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    sender_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    recipient_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)  # Добавляем колонку is_read

# Модель для групповых чатов
class GroupChat(Base):
    __tablename__ = 'group_chats'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    creator_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    participants = relationship("User", secondary="group_chat_participants")


group_chat_participants = Table(
    'group_chat_participants',
    Base.metadata,
    Column('group_chat_id', Integer, ForeignKey('group_chats.id')),
    Column('user_id', Integer, ForeignKey('users.id'))
)

# Модель для сообщений в групповых чатах
class GroupMessage(Base):
    __tablename__ = 'group_messages'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    group_chat_id: Mapped[int] = mapped_column(Integer, ForeignKey("group_chats.id"))
    sender_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    content: Mapped[str] = mapped_column(Text)
    #is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)  # Добавляем это поле
    sender = relationship("User", backref="group_messages", lazy="joined")


class GroupMessageReadStatus(Base):
    __tablename__ = 'group_message_reads'

    id = Column(Integer, primary_key=True)
    message_id = Column(Integer, ForeignKey('group_messages.id'), nullable=False)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    read_at = Column(DateTime)
    group_chat_id = Column(Integer, ForeignKey('group_chats.id'))
    sender_id = Column(Integer, ForeignKey('users.id'))
    sender_name = Column(String)
    content = Column(Text)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime)