import logging

from fastapi import APIRouter, Depends

from app.push.dao import PushTokenDAO
from app.push.service import PushNotificationService
from app.push.schemas import PushTokenDelete, PushTokenRegister
from app.users.dependensies_user import get_current_user
from app.users.models_user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/push", tags=["Push"])
logger = logging.getLogger(__name__)


def _short_token(token: str | None) -> str:
    if not token:
        return "<empty>"
    if len(token) <= 12:
        return token
    return f"{token[:6]}...{token[-6:]}"


@router.post("/tokens")
async def register_push_token(
    payload: PushTokenRegister,
    current_user: User = Depends(get_current_user),
):
    logger.info(
        "Register push token: user=%s platform=%s token=%s device_id=%s",
        current_user.id,
        payload.platform,
        _short_token(payload.token),
        payload.device_id,
    )
    await PushTokenDAO.upsert_token(
        user_id=current_user.id,
        token=payload.token,
        platform=payload.platform,
        device_id=payload.device_id,
    )
    return {"status": "ok"}


@router.post("/tokens/delete")
async def delete_push_token(
    payload: PushTokenDelete,
    current_user: User = Depends(get_current_user),
):
    logger.info(
        "Deactivate push token: user=%s token=%s",
        current_user.id,
        _short_token(payload.token),
    )
    await PushTokenDAO.deactivate_token(payload.token, user_id=current_user.id)
    logger.info(
        "Push: токен удалён для пользователя %s (token=…%s)",
        current_user.id,
        payload.token[-8:] if payload.token else "?",
    )
    return {"status": "ok"}


@router.post("/debug/send_test")
async def send_debug_push(current_user: User = Depends(get_current_user)):
    logger.info("Debug push requested: user=%s", current_user.id)
    result = await PushNotificationService.send_debug_push(current_user.id)
    return {"status": "ok", **result}
