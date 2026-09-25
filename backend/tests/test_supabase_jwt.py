import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec, rsa

from askmedi.adapters.supabase_jwt import SupabaseJwtVerifier
from askmedi.domain.auth import InvalidToken

ISSUER = "https://proj.supabase.co/auth/v1"
AUD = "authenticated"


@pytest.fixture(scope="module")
def keypair():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private, private.public_key()


def make_token(private_key, **overrides) -> str:
    now = int(time.time())
    claims = {
        "sub": "user-123",
        "email": "a@test.dev",
        "aud": AUD,
        "iss": ISSUER,
        "iat": now,
        "exp": now + 3600,
        "role": "authenticated",
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, private_key, algorithm="RS256")


@pytest.fixture
def verifier(keypair):
    _, public = keypair
    return SupabaseJwtVerifier(issuer=ISSUER, audience=AUD, key_resolver=lambda _t: public)


def test_valid_token_returns_user(verifier, keypair):
    user = verifier.verify(make_token(keypair[0]))
    assert user.user_id == "user-123"
    assert user.email == "a@test.dev"


def test_expired_token_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], exp=int(time.time()) - 10))


def test_wrong_audience_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], aud="anon"))


def test_wrong_issuer_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], iss="https://evil.example/auth/v1"))


def test_token_signed_by_other_key_rejected(verifier):
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(other))


def test_missing_sub_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], sub=None))


def test_garbage_rejected(verifier):
    with pytest.raises(InvalidToken):
        verifier.verify("not-a-jwt")


def test_es256_token_verifies():
    # Supabase issues ES256 access tokens; pin that this algorithm keeps working.
    private = ec.generate_private_key(ec.SECP256R1())
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": "user-es",
            "email": "es@test.dev",
            "aud": AUD,
            "iss": ISSUER,
            "iat": now,
            "exp": now + 3600,
        },
        private,
        algorithm="ES256",
    )
    es_verifier = SupabaseJwtVerifier(
        issuer=ISSUER, audience=AUD, key_resolver=lambda _t: private.public_key()
    )
    user = es_verifier.verify(token)
    assert user.user_id == "user-es"
    assert user.email == "es@test.dev"


def test_empty_sub_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], sub=""))


def test_blank_sub_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], sub="   "))


def test_non_string_sub_rejected(verifier, keypair):
    with pytest.raises(InvalidToken):
        verifier.verify(make_token(keypair[0], sub=123))
