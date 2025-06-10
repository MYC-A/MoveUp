from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.exceptions import HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles


from app.db.base import init_db
from app.exceptions import TokenExpiredException, TokenNoFoundException
from app.lk.routes_profile import router as profile_router
from app.users.router_users import router as users_router
from app.chat.router import router as chat_router
from app.posts.routes_posts import router as post_router
from app.event.routers_event import router as event_router
from app.friendship.routes_friends import router as friends_router
app = FastAPI()
app.mount('/static', StaticFiles(directory='app/static'), name='static')

# Инициализация базы данных при запуске приложения
@app.on_event("startup")
async def on_startup():
    await init_db()


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Разрешить запросы с любых источников. Можете ограничить список доменов
    allow_credentials=True,
    allow_methods=["*"],  # Разрешить все методы (GET, POST, PUT, DELETE и т.д.)
    allow_headers=["*"],  # Разрешить все заголовки
)

app.include_router(users_router)
app.include_router(chat_router)
app.include_router(post_router)
app.include_router(profile_router)
app.include_router(friends_router)
app.include_router(event_router)


@app.get("/")
async def redirect_to_auth():
    return RedirectResponse(url="/auth")


@app.exception_handler(TokenExpiredException)
async def token_expired_exception_handler(request: Request, exc: HTTPException):
    # Возвращаем редирект на страницу /auth
    return RedirectResponse(url="/auth")


# Обработчик для TokenNoFound
@app.exception_handler(TokenNoFoundException)
async def token_no_found_exception_handler(request: Request, exc: HTTPException):
    # Возвращаем редирект на страницу /auth
    return RedirectResponse(url="/auth")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
