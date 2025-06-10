from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Optional

# Базовый класс для данных валидации данных пользователя
class UserBase(BaseModel):
    email: EmailStr = Field(..., description="Электронная почта")
    username: str = Field(..., min_length=3, max_length=50, description="Имя пользователя, от 3 до 50 символов")
    full_name: Optional[str] = Field(None, description="Полное имя")
    bio: Optional[str] = Field(None, description="Биография")
    avatar_url: Optional[str] = Field(None, description="Ссылка на аватар")

"""
class UserRead(BaseModel):
    id: int = Field(..., description="Идентификатор пользователя")
    full_name: str = Field(..., min_length=3, max_length=50, description="Имя, от 3 до 50 символов")

"""
# Схема для регистрации пользователя
class UserRegister(BaseModel):
    email: EmailStr = Field(..., description="Электронная почта")
    password: str = Field(..., min_length=5, max_length=50, description="Пароль, от 5 до 50 знаков")
    password_check: str = Field(..., min_length=5, max_length=50, description="Пароль, от 5 до 50 знаков")
    full_name: str = Field(..., min_length=3, max_length=50, description="Имя, от 3 до 50 символов")


# Схема для аутентификации пользователя
class UserAuth(BaseModel):
    email: EmailStr = Field(..., description="Электронная почта")
    password: str = Field(..., min_length=5, max_length=50, description="Пароль, от 5 до 50 знаков")

# Схема для создания пользователя (без подтверждения пароля)
class UserCreate(UserBase):
    password: str = Field(..., min_length=5, max_length=50, description="Пароль, от 5 до 50 знаков")

# Схема для обновления данных пользователя
class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(None, description="Полное имя")
    bio: Optional[str] = Field(None, description="Биография")
    avatar_url: Optional[str] = Field(None, description="Ссылка на аватар")

# Схема для данных пользователя в базе данных
class UserInDB(UserBase):
    id: str = Field(..., description="Идентификатор пользователя")
    created_at: datetime = Field(..., description="Дата и время создания")
    is_active: bool = Field(..., description="Активен ли пользователь")

    class Config:
        from_attributes = True  # Для совместимости с ORM (ранее `orm_mode = True`)


class UserRead(BaseModel):
    id: int
    full_name: str
    avatar_url: str | None = None

    class Config:
        from_attributes = True  # Ранее known as `orm_mode = True`