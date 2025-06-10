from datetime import datetime
from typing import Dict, List

from sqlalchemy import select, and_, or_, update, func, literal, exists
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import joinedload

from app.chat.models import Message, GroupMessage, GroupChat, group_chat_participants, GroupMessageReadStatus
from app.chat.schemas import GroupMessageRead
from app.dao.base import BaseDAO
from app.db.base import async_session_maker
from app.users.models_user import User #Надо поменть на папку в нутри chat


class MessagesDAO(BaseDAO):
    model = Message

    @classmethod
    async def get_users_with_messages(cls, user_id: int):
        """
        Асинхронно находит и возвращает список пользователей, с которыми у текущего пользователя есть переписка.

        Аргументы:
            user_id: ID текущего пользователя.

        Возвращает:
            Список пользователей, с которыми есть переписка.
        """
        async with async_session_maker() as session:
            # Находим всех пользователей, с которыми есть переписка
            query = select(User).join(
                cls.model,
                or_(
                    User.id == cls.model.sender_id,
                    User.id == cls.model.recipient_id
                )
            ).filter(
                or_(
                    cls.model.sender_id == user_id,
                    cls.model.recipient_id == user_id
                )
            ).distinct()
            result = await session.execute(query)
            return result.scalars().all()

    @classmethod
    async def find_by_ids(cls, user_ids: list[int]):
        """
        Асинхронно находит и возвращает список пользователей по их идентификаторам.

        Аргументы:
            user_ids: Список идентификаторов пользователей.

        Возвращает:
            Список пользователей.
        """
        async with async_session_maker() as session:
            query = select(cls.model).filter(cls.model.id.in_(user_ids))
            result = await session.execute(query)
            return result.scalars().all()
    @classmethod
    async def get_messages_between_users(cls, user_id_1: int, user_id_2: int):
        """
        Асинхронно находит и возвращает все сообщения между двумя пользователями.

        Аргументы:
            user_id_1: ID первого пользователя.
            user_id_2: ID второго пользователя.

        Возвращает:
            Список сообщений между двумя пользователями.
        """
        async with async_session_maker() as session:
            query = select(cls.model).filter(
                or_(
                    and_(cls.model.sender_id == user_id_1, cls.model.recipient_id == user_id_2),
                    and_(cls.model.sender_id == user_id_2, cls.model.recipient_id == user_id_1)
                )
            ).order_by(cls.model.id)
            result = await session.execute(query)
            return result.scalars().all()

    # Пример mark_messages_as_read
    @classmethod
    async def mark_messages_as_read(cls, user_id: int, recipient_id: int):
        print("Сообщение прочитано")
        """
        Помечает сообщения как прочитанные.

        Аргументы:
            user_id: ID текущего пользователя.
            recipient_id: ID отправителя сообщений.
        """
        async with async_session_maker() as session:
            query = update(cls.model).where(
                (cls.model.sender_id == recipient_id) &
                (cls.model.recipient_id == user_id) &
                (cls.model.is_read == False)  # Только непрочитанные
            ).values(is_read=True)
            await session.execute(query)
            await session.commit()

    # В MessagesDAO
    @classmethod
    async def get_unread_messages_count(cls, user_id: int) -> Dict[str, Dict[int, int]]:
        async with async_session_maker() as session:
            # Подсчёт непрочитанных групповых сообщений
            group_query = select(
                GroupMessage.group_chat_id,
                func.count(GroupMessage.id)
            ).join(
                group_chat_participants,
                GroupMessage.group_chat_id == group_chat_participants.c.group_chat_id
            ).join(
                GroupMessageReadStatus,
                (GroupMessage.id == GroupMessageReadStatus.message_id) &
                (GroupMessageReadStatus.user_id == user_id)
            ).where(
                (group_chat_participants.c.user_id == user_id) &
                (GroupMessageReadStatus.is_read == False)
            ).group_by(GroupMessage.group_chat_id)

            group_result = await session.execute(group_query)
            group_unread = {row[0]: row[1] for row in group_result}

            # Подсчёт непрочитанных личных сообщений
            personal_query = select(
                Message.sender_id,
                func.count(Message.id)
            ).where(
                (Message.recipient_id == user_id) &
                (Message.is_read == False)
            ).group_by(Message.sender_id)

            personal_result = await session.execute(personal_query)
            personal_unread = {row[0]: row[1] for row in personal_result}

            print(
                f"Непрочитанные сообщения для пользователя {user_id}: personal={personal_unread}, group={group_unread}")
            return {
                "personal": personal_unread,
                "group": group_unread
            }




class GroupMessagesDAO(BaseDAO):
    model = GroupMessage

    @classmethod
    async def get_user_group_chats(cls, user_id: int):
        """
        Возвращает список групповых чатов, в которых участвует пользователь.
        """
        async with async_session_maker() as session:
            query = select(GroupChat).join(
                group_chat_participants,
                group_chat_participants.c.group_chat_id == GroupChat.id
            ).filter(
                group_chat_participants.c.user_id == user_id
            )
            result = await session.execute(query)
            return result.scalars().all()

    @classmethod
    async def add_participants_to_group_chat(cls, group_chat_id: int, participants: List[int]):
        async with async_session_maker() as session:
            for participant_id in participants:
                session.execute(
                    group_chat_participants.insert().values(
                        group_chat_id=group_chat_id,
                        user_id=participant_id
                    )
                )
            await session.commit()

    from sqlalchemy.orm import joinedload

    # В GroupMessagesDAO
    @classmethod
    async def get_group_messages(cls, group_chat_id: int, current_user_id: int):
        async with async_session_maker() as session:
            query = (
                select(
                    GroupMessage.id,
                    GroupMessage.group_chat_id,
                    GroupMessage.sender_id,
                    User.full_name.label("sender_name"),
                    GroupMessage.content,
                    GroupMessageReadStatus.message_id.isnot(None).label("is_read"),
                    GroupMessage.created_at
                )
                .join(User, GroupMessage.sender_id == User.id)
                .outerjoin(
                    GroupMessageReadStatus,
                    (GroupMessage.id == GroupMessageReadStatus.message_id) &
                    (GroupMessageReadStatus.user_id == current_user_id)
                )
                .where(GroupMessage.group_chat_id == group_chat_id)
                .order_by(GroupMessage.created_at)
            )
            result = await session.execute(query)
            return [
                GroupMessageRead(
                    id=row.id,
                    group_chat_id=row.group_chat_id,
                    sender_id=row.sender_id,
                    sender_name=row.sender_name,
                    content=row.content,
                    is_read=row.is_read if row.sender_id != current_user_id else True,
                    created_at=row.created_at
                )
                for row in result.all()
            ]

    # В GroupMessagesDAO
    # В методе mark_group_messages_as_read


    @classmethod
    async def mark_group_messages_as_read(cls, group_chat_id: int, user_id: int):
        async with async_session_maker() as session:
            stmt = (
                update(GroupMessageReadStatus)
                .where(
                    GroupMessageReadStatus.user_id == user_id,
                    GroupMessageReadStatus.group_chat_id == group_chat_id,
                    GroupMessageReadStatus.is_read == False
                )
                .values(is_read=True, read_at=func.now())
                .returning(GroupMessageReadStatus.message_id)
            )

            result = await session.execute(stmt)
            marked_count = len(result.fetchall())
            await session.commit()

            print(
                f"Помечено как прочитанные: {marked_count} сообщений для чата {group_chat_id} и пользователя {user_id}")
            return marked_count

    @classmethod
    async def add_group_message(cls, group_chat_id: int, sender_id: int, content: str):
        async with async_session_maker() as session:
            # Проверяем, существует ли чат
            group_chat = await session.execute(
                select(GroupChat).where(GroupChat.id == group_chat_id)
            )
            group_chat = group_chat.scalar_one_or_none()

            if not group_chat:
                raise ValueError("Групповой чат не найден")

            # Проверяем, является ли отправитель участником чата
            participant = await session.execute(
                select(group_chat_participants).where(
                    (group_chat_participants.c.group_chat_id == group_chat_id) &
                    (group_chat_participants.c.user_id == sender_id)
                )
            )
            participant = participant.scalar_one_or_none()

            if not participant:
                raise ValueError("Отправитель не является участником чата")

            # Добавляем сообщение
            group_message = GroupMessage(
                group_chat_id=group_chat_id,
                sender_id=sender_id,
                content=content,
                created_at=datetime.utcnow()
            )
            session.add(group_message)
            await session.commit()
            return group_message

    @classmethod
    async def get_group_chat_participants(cls, group_chat_id: int):
        async with async_session_maker() as session:
            query = select(group_chat_participants.c.user_id).where(group_chat_participants.c.group_chat_id == group_chat_id)
            result = await session.execute(query)
            return result.scalars().all()

    @classmethod
    async def create_group_chat(cls, name: str, creator_id: int, participants: List[int]):
        async with async_session_maker() as session:
            group_chat = GroupChat(name=name, creator_id=creator_id)
            session.add(group_chat)
            await session.flush()  # Нужно для получения group_chat.id

            # Добавляем создателя в участники
            await session.execute(  # <-- добавил await
                group_chat_participants.insert().values(
                    group_chat_id=group_chat.id,
                    user_id=creator_id
                )
            )

            # Добавляем остальных участников (если они есть)
            for participant_id in participants:
                await session.execute(  # <-- добавил await
                    group_chat_participants.insert().values(
                        group_chat_id=group_chat.id,
                        user_id=participant_id
                    )
                )

            await session.commit()  # Коммитим изменения
            return group_chat.id

    @classmethod
    async def add_participant_to_group_chat(cls, group_chat_id: int, user_id: int):
        async with async_session_maker() as session:
            await session.execute(  # Добавлен await перед session.execute
                group_chat_participants.insert().values(
                    group_chat_id=group_chat_id,
                    user_id=user_id
                )
            )
            await session.commit()
