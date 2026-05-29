"""Валидация загружаемых изображений (аватары, фото постов).

Клиентский content_type подделывается, поэтому помимо MIME проверяем
расширение и сигнатуру (magic bytes), а также ограничиваем размер файла.
"""
from fastapi import HTTPException, UploadFile

# 10 МБ — разумный лимит для фото в мобильном приложении.
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024

ALLOWED_IMAGE_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/gif",
}

ALLOWED_IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "gif"}

# Сигнатуры начала файла для популярных форматов изображений.
_IMAGE_MAGIC_BYTES = (
    b"\xff\xd8\xff",          # JPEG
    b"\x89PNG\r\n\x1a\n",     # PNG
    b"GIF87a",                # GIF
    b"GIF89a",                # GIF
    b"RIFF",                  # WEBP (RIFF....WEBP)
)


def _has_image_signature(content: bytes) -> bool:
    return any(content.startswith(sig) for sig in _IMAGE_MAGIC_BYTES)


def validate_image_upload(file: UploadFile, content: bytes) -> None:
    """Бросает HTTPException(400), если файл не похож на допустимое изображение."""
    if not content:
        raise HTTPException(status_code=400, detail="Пустой файл")

    if len(content) > MAX_IMAGE_SIZE_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"Файл слишком большой (макс. {MAX_IMAGE_SIZE_BYTES // (1024 * 1024)} МБ)",
        )

    content_type = (file.content_type or "").lower()
    if content_type and content_type not in ALLOWED_IMAGE_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail="Недопустимый тип файла")

    extension = ""
    if file.filename and "." in file.filename:
        extension = file.filename.rsplit(".", 1)[-1].lower()
    if extension and extension not in ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Недопустимое расширение файла")

    if not _has_image_signature(content):
        raise HTTPException(status_code=400, detail="Файл не является изображением")
