"""Тесты хеширования паролей и создания токена."""
from datetime import timedelta

from jose import jwt

from app.core.config import settings
from app.users.auth_users import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
)


def test_password_hash_roundtrip():
    hashed = get_password_hash("super-secret")
    assert hashed != "super-secret"
    assert verify_password("super-secret", hashed)
    assert not verify_password("wrong-password", hashed)


def test_access_token_contains_subject():
    token = create_access_token({"sub": "42"}, expires_delta=timedelta(minutes=5))
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    assert payload["sub"] == "42"
    assert "exp" in payload
    assert payload["type"] == "access"


def test_refresh_token_has_type():
    token = create_refresh_token({"sub": "7"})
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    assert payload["sub"] == "7"
    assert payload["type"] == "refresh"
