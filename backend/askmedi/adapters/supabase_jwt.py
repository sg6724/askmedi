from collections.abc import Callable
from typing import Any, ClassVar

import jwt

from askmedi.domain.auth import AuthUser, InvalidToken

KeyResolver = Callable[[str], Any]


def jwks_key_resolver(jwks_url: str) -> KeyResolver:
    """Resolve the signing key for a token from Supabase's JWKS endpoint (cached)."""
    client = jwt.PyJWKClient(jwks_url, cache_keys=True, lifespan=3600)

    def resolve(token: str) -> Any:
        return client.get_signing_key_from_jwt(token).key

    return resolve


class SupabaseJwtVerifier:
    ALGORITHMS: ClassVar[list[str]] = ["ES256", "RS256"]

    def __init__(self, issuer: str, audience: str, key_resolver: KeyResolver) -> None:
        self._issuer = issuer
        self._audience = audience
        self._key_resolver = key_resolver

    def verify(self, token: str) -> AuthUser:
        try:
            key = self._key_resolver(token)
            claims = jwt.decode(
                token,
                key,
                algorithms=self.ALGORITHMS,
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "sub", "aud", "iss"]},
            )
        except jwt.PyJWTError as exc:
            raise InvalidToken(str(exc)) from exc
        sub = claims["sub"]
        if not isinstance(sub, str) or not sub.strip():
            raise InvalidToken("token subject is missing or empty")
        return AuthUser(user_id=sub, email=claims.get("email"), claims=claims)
