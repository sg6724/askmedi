"""Upload validation shared by the multipart endpoints."""

import mimetypes

from fastapi import HTTPException, UploadFile

IMAGE_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
PDF_TYPES = frozenset({"application/pdf"})
AUDIO_TYPES = frozenset(
    {
        "audio/webm",
        "audio/ogg",
        "audio/mp4",
        "audio/m4a",
        "audio/x-m4a",
        "audio/aac",
        "audio/mpeg",
        "audio/mp3",
        "audio/wav",
        "audio/x-wav",
        "audio/wave",
        "video/webm",
    }
)
_EXTENSIONS = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
    ".webm": "audio/webm",
    ".ogg": "audio/ogg",
    ".oga": "audio/ogg",
    ".opus": "audio/ogg",
    ".m4a": "audio/mp4",
    ".mp4": "audio/mp4",
    ".aac": "audio/aac",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
}


def _sniff(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return "audio/wav"
    if data.startswith(b"%PDF"):
        return "application/pdf"
    if data.startswith(b"OggS"):
        return "audio/ogg"
    if data.startswith(b"\x1a\x45\xdf\xa3"):
        return "audio/webm"
    if data.startswith(b"ID3") or data[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
        return "audio/mpeg"
    if data[4:8] == b"ftyp":
        return "audio/mp4"
    return None


def resolve_mime(upload: UploadFile, data: bytes, allowed: frozenset[str]) -> str | None:
    """Declared type first; mobile clients often send application/octet-stream, so fall back to
    the file extension and then to magic bytes."""
    declared = (upload.content_type or "").split(";")[0].strip().lower()
    if declared in allowed:
        return declared
    ext = mimetypes.guess_extension(declared) if declared else None
    name = (upload.filename or "").lower()
    for suffix, mime in _EXTENSIONS.items():
        if name.endswith(suffix) and mime in allowed:
            return mime
    if ext and _EXTENSIONS.get(ext) in allowed:
        return _EXTENSIONS[ext]
    sniffed = _sniff(data)
    return sniffed if sniffed in allowed else None


async def read_upload(
    upload: UploadFile, *, allowed: frozenset[str], max_bytes: int
) -> tuple[bytes, str]:
    data = await upload.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(413, "file_too_large")
    mime = resolve_mime(upload, data, allowed)
    if mime is None:
        raise HTTPException(415, "unsupported_media_type")
    if not data:
        raise HTTPException(422, "empty_file")
    return data, mime
