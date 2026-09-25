from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, StringConstraints

from askmedi.api.deps import CurrentUser, get_container
from askmedi.api.schemas import LanguageField
from askmedi.api.uploads import AUDIO_TYPES, read_upload
from askmedi.container import Container
from askmedi.services.voice import VoiceService

router = APIRouter(prefix="/voice")

MAX_AUDIO_BYTES = 10 * 1024 * 1024
SpeakText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1500)]


class SpeakIn(BaseModel):
    text: SpeakText
    language: LanguageField = "en"


def _service(container: Annotated[Container, Depends(get_container)]) -> VoiceService:
    if container.voice is None:
        raise HTTPException(503, "voice_unavailable")
    container.voice.ensure_available()
    return container.voice


Service = Annotated[VoiceService, Depends(_service)]


@router.post("/transcribe")
async def transcribe(
    user: CurrentUser,
    service: Service,
    audio: Annotated[UploadFile, File()],
    language: Annotated[LanguageField | None, Form()] = None,
) -> dict[str, str]:
    """`language` is an optional hint; the detected language is returned either way."""
    data, mime = await read_upload(audio, allowed=AUDIO_TYPES, max_bytes=MAX_AUDIO_BYTES)
    return await service.transcribe(user.user_id, data, audio.filename or "audio", mime, language)


@router.post("/speak")
async def speak(body: SpeakIn, user: CurrentUser, service: Service) -> Response:
    audio = await service.speak(user.user_id, body.text, body.language)
    return Response(content=audio, media_type="audio/mpeg")
