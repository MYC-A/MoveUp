from app.dao.base import BaseDAO
from app.users.models_user import User #Надо поменть на папку в нутри chat


class UsersDAO(BaseDAO):
    model = User