#post/schemas_comments.py
from datetime import datetime

from pydantic import BaseModel

class CommentCreate(BaseModel):
    content: str

