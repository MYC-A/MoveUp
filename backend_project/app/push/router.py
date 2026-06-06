import logging

from fastapi import APIRouter, Depends

from app.push.dao import PushTokenDAO
from app.push.schemas import PushTokenDelete, PushTokenRegister
from app.users.dependensies_user import get_current_user
from app.users.models_user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/push", tags=["Push"])


@router.post("/tokens")
async def register_push_token(
    payload: PushTokenRegister,
    current_user: User = Depends(get_current_user),
):
    await PushTokenDAO.upsert_token(
        user_id=current_user.id,
        token=payload.token,
        platform=payload.platform,
        device_id=payload.device_id,
    )
    logger.info(
        "Push: токен зарегистрирован для пользователя %s (platform=%s, token=…%s)",
        current_user.id,
        payload.platform,
        payload.token[-8:] if payload.token else "?",
    )
    return {"status": "ok"}


@router.post("/tokens/delete")
async def delete_push_token(
    payload: PushTokenDelete,
    current_user: User = Depends(get_current_user),
):
    await PushTokenDAO.deactivate_token(payload.token, user_id=current_user.id)
    logger.info(
        "Push: токен удалён для пользователя %s (token=…%s)",
        current_user.id,
        payload.token[-8:] if payload.token else "?",
    )
    return {"status": "ok"}
