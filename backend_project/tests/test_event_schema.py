"""Тесты валидации схемы создания мероприятия (route_data)."""
import pytest
from pydantic import ValidationError

from app.event.schemas_event import EventCreate, EventType, MAX_ROUTE_DISTANCE_KM


def _payload(**overrides):
    data = dict(
        title="Тестовый забег",
        event_type=EventType.RUNNING,
        difficulty="новичок",
        max_participants=10,
        city=None,  # пропускаем валидацию города
        route_data=[
            {"latitude": 55.7558, "longitude": 37.6173},
            {"latitude": 55.7560, "longitude": 37.6180},
        ],
    )
    data.update(overrides)
    return data


def test_short_route_accepted():
    event = EventCreate(**_payload())
    assert len(event.route_data) == 2


def test_latitude_out_of_bounds_rejected():
    with pytest.raises(ValidationError):
        EventCreate(**_payload(route_data=[{"latitude": 200.0, "longitude": 37.6}]))


def test_longitude_out_of_bounds_rejected():
    with pytest.raises(ValidationError):
        EventCreate(**_payload(route_data=[{"latitude": 55.0, "longitude": 999.0}]))


def test_route_longer_than_limit_rejected():
    # Две точки на разных полушариях — заведомо больше лимита в км.
    with pytest.raises(ValidationError):
        EventCreate(
            **_payload(
                route_data=[
                    {"latitude": 0.0, "longitude": 0.0},
                    {"latitude": 0.0, "longitude": 90.0},
                ]
            )
        )


def test_max_route_distance_constant_is_positive():
    assert MAX_ROUTE_DISTANCE_KM > 0
