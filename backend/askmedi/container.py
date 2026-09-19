from dataclasses import dataclass

from askmedi.config import Settings
from askmedi.domain.audit import AuditLogger
from askmedi.domain.auth import TokenVerifier
from askmedi.domain.llm import LLMProvider


@dataclass
class Container:
    token_verifier: TokenVerifier
    llm: LLMProvider
    audit: AuditLogger


def build_container(settings: Settings) -> Container:
    # Imported here so domain-only imports of Container stay dependency-free.
    from askmedi.adapters.database import Database
    from askmedi.adapters.litellm_provider import LiteLLMProvider
    from askmedi.adapters.postgres_audit import PostgresAuditLogger
    from askmedi.adapters.supabase_jwt import SupabaseJwtVerifier, jwks_key_resolver

    # Database is constructed exactly once, here, and shared through the audit
    # logger; never build one per request. Its connection pool opens lazily and
    # binds to the event loop of the first request, so the app relies on one
    # long-lived event loop per process.
    db = Database(settings.database_url)
    return Container(
        token_verifier=SupabaseJwtVerifier(
            issuer=settings.supabase_issuer,
            audience=settings.jwt_audience,
            key_resolver=jwks_key_resolver(settings.supabase_jwks_url),
        ),
        llm=LiteLLMProvider.from_yaml(settings.models_config_path),
        audit=PostgresAuditLogger(db),
    )
