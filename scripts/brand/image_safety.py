"""Fail-closed image input checks shared by brand tooling."""

from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image


MAX_IMAGE_FILE_BYTES = 16 * 1024 * 1024
MAX_IMAGE_PIXELS = 8192 * 8192
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
TIFF_MAGICS = (b"II*\x00", b"MM\x00*")


class UnsafeImageError(ValueError):
    """Raised before decoding an unsupported or excessive image input."""


def open_image(path: Path, expected_format: str) -> Image.Image:
    validate_image_input(path, expected_format)
    try:
        return Image.open(path, formats=(expected_format,))
    except (OSError, SyntaxError, Image.DecompressionBombError) as error:
        raise UnsafeImageError(f"invalid {expected_format}: {path}: {error}") from error


def validate_image_input(path: Path, expected_format: str) -> tuple[int, int]:
    size = path.stat().st_size
    if size > MAX_IMAGE_FILE_BYTES:
        raise UnsafeImageError(f"image file too large: expected <= {MAX_IMAGE_FILE_BYTES} bytes, got {size}")

    data = path.read_bytes()
    dimensions = image_dimensions(data, expected_format)
    if dimensions is None:
        raise UnsafeImageError(f"wrong {expected_format} file signature or header")

    width, height = dimensions
    if width <= 0 or height <= 0 or width * height > MAX_IMAGE_PIXELS:
        raise UnsafeImageError(f"image pixel limit exceeded: expected <= {MAX_IMAGE_PIXELS}, got {width}x{height}")
    return dimensions


def image_dimensions(data: bytes, expected_format: str) -> tuple[int, int] | None:
    if expected_format == "PNG":
        if len(data) < 24 or not data.startswith(PNG_MAGIC) or data[12:16] != b"IHDR":
            return None
        return struct.unpack_from(">II", data, 16)
    if expected_format == "TIFF":
        return tiff_dimensions(data)
    return None


def tiff_dimensions(data: bytes) -> tuple[int, int] | None:
    if len(data) < 8 or data[:4] not in TIFF_MAGICS:
        return None
    byte_order = "<" if data[:2] == b"II" else ">"
    ifd_offset = struct.unpack_from(f"{byte_order}I", data, 4)[0]
    if ifd_offset + 2 > len(data):
        return None
    entry_count = struct.unpack_from(f"{byte_order}H", data, ifd_offset)[0]
    width = tiff_tag_value(data, byte_order, ifd_offset, entry_count, 256)
    height = tiff_tag_value(data, byte_order, ifd_offset, entry_count, 257)
    if width is None or height is None:
        return None
    return width, height


def tiff_tag_value(
    data: bytes,
    byte_order: str,
    ifd_offset: int,
    entry_count: int,
    target_tag: int,
) -> int | None:
    for index in range(entry_count):
        offset = ifd_offset + 2 + index * 12
        if offset + 12 > len(data):
            return None
        tag, value_type, count = struct.unpack_from(f"{byte_order}HHI", data, offset)
        if tag != target_tag or count != 1 or value_type not in (3, 4):
            continue
        if value_type == 3:
            return struct.unpack_from(f"{byte_order}H", data, offset + 8)[0]
        return struct.unpack_from(f"{byte_order}I", data, offset + 8)[0]
    return None
