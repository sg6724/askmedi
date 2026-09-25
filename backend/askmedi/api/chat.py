from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, StringConstraints

from askmedi.api.deps import CurrentUser, get_container
from askmedi.api.schemas import LanguageField
from askmedi.container import Container
from askmedi.services.chat import ChatRequest

router = APIRouter()

Message = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


class ChatIn(BaseModel):
    episode_id: UUID | None = None
    message: Message
    language: LanguageField = "en"


@router.post("/chat")
async def chat(
    body: ChatIn, user: CurrentUser, container: Annotated[Container, Depends(get_container)]
) -> dict[str, Any]:
    if container.chat is None:
        raise HTTPException(503, "service_unavailable")
    return await container.chat.handle(
        ChatRequest(
            user_id=user.user_id,
            episode_id=str(body.episode_id) if body.episode_id else None,
            message=body.message,
            language=body.language,
        )
    )
