from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class AuthUser:
    user_id: str
    email: str | None
    claims: dict[str, Any] = field(default_factory=dict)


class InvalidToken(Exception):
    """Raised when a bearer token is missing, malformed, expired or untrusted."""


class TokenVerifier(Protocol):
    def verify(self, token: str) -> AuthUser: ...
