from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status

from askmedi.container import Container
from askmedi.domain.auth import AuthUser, InvalidToken


def get_container(request: Request) -> Container:
    return request.app.state.container


def get_current_user(
    container: Annotated[Container, Depends(get_container)],
    authorization: Annotated[str | None, Header()] = None,
) -> AuthUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        return container.token_verifier.verify(token)
    except InvalidToken:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token") from None


CurrentUser = Annotated[AuthUser, Depends(get_current_user)]
