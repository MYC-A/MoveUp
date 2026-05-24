from typing import Literal

from pydantic import BaseModel, Field


class PushTokenRegister(BaseModel):
    token: str = Field(..., min_length=20)
    platform: Literal["android", "ios", "web"] = "android"
    device_id: str | None = None


class PushTokenDelete(BaseModel):
    token: str = Field(..., min_length=20)
