"""Тесты валидации загружаемых изображений (app.core.uploads)."""
import pytest
from fastapi import HTTPException

from app.core.uploads import validate_image_upload, MAX_IMAGE_SIZE_BYTES

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"0" * 32
JPEG_BYTES = b"\xff\xd8\xff" + b"0" * 32


class _FakeUpload:
    def __init__(self, filename, content_type):
        self.filename = filename
        self.content_type = content_type


def test_valid_png_passes():
    validate_image_upload(_FakeUpload("photo.png", "image/png"), PNG_BYTES)


def test_valid_jpeg_passes():
    validate_image_upload(_FakeUpload("photo.jpg", "image/jpeg"), JPEG_BYTES)


def test_empty_file_rejected():
    with pytest.raises(HTTPException):
        validate_image_upload(_FakeUpload("photo.png", "image/png"), b"")


def test_oversized_file_rejected():
    big = b"\x89PNG\r\n\x1a\n" + b"0" * (MAX_IMAGE_SIZE_BYTES + 1)
    with pytest.raises(HTTPException):
        validate_image_upload(_FakeUpload("photo.png", "image/png"), big)


def test_bad_extension_rejected():
    with pytest.raises(HTTPException):
        validate_image_upload(_FakeUpload("malware.exe", "image/png"), PNG_BYTES)


def test_bad_content_type_rejected():
    with pytest.raises(HTTPException):
        validate_image_upload(
            _FakeUpload("photo.png", "application/octet-stream"), PNG_BYTES
        )


def test_non_image_payload_rejected():
    with pytest.raises(HTTPException):
        validate_image_upload(_FakeUpload("photo.png", "image/png"), b"not-an-image")
