"""Тесты валидации auth-схем: регистрация (рост/вес/город) и смена пароля."""
import pytest
from pydantic import ValidationError

from app.users.schemas_user import (
    UserRegister, EmailVerify, EmailResend, PasswordChange,
)


def _reg(**overrides):
    data = dict(
        email="runner@example.com",
        password="secret",
        password_check="secret",
        full_name="Иван Бегунов",
    )
    data.update(overrides)
    return data


def test_register_minimal_ok():
    user = UserRegister(**_reg())
    assert user.city is None and user.weight is None and user.height is None


def test_register_with_body_fields_ok():
    user = UserRegister(**_reg(city="Москва", weight=72.5, height=180))
    assert user.weight == 72.5 and user.height == 180


def test_register_weight_out_of_range_rejected():
    with pytest.raises(ValidationError):
        UserRegister(**_reg(weight=500))
    with pytest.raises(ValidationError):
        UserRegister(**_reg(weight=10))


def test_register_height_out_of_range_rejected():
    with pytest.raises(ValidationError):
        UserRegister(**_reg(height=500))
    with pytest.raises(ValidationError):
        UserRegister(**_reg(height=50))


def test_register_short_password_rejected():
    with pytest.raises(ValidationError):
        UserRegister(**_reg(password="123", password_check="123"))


def test_email_verify_requires_code():
    EmailVerify(email="a@b.com", code="123456")
    with pytest.raises(ValidationError):
        EmailVerify(email="a@b.com", code="")


def test_email_resend_ok():
    assert EmailResend(email="a@b.com").email == "a@b.com"


def test_password_change_min_length():
    PasswordChange(old_password="oldpass", new_password="newpass")
    with pytest.raises(ValidationError):
        PasswordChange(old_password="x", new_password="y")
