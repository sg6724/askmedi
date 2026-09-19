from askmedi.adapters.litellm_provider import LiteLLMProvider
from askmedi.adapters.postgres_audit import PostgresAuditLogger
from askmedi.adapters.supabase_jwt import SupabaseJwtVerifier
from askmedi.config import Settings
from askmedi.container import build_container


def test_build_container_wires_real_adapters():
    settings = Settings(
        supabase_url="https://proj.supabase.co",
        database_url="postgresql://u:p@localhost:5432/db",
    )
    container = build_container(settings)
    assert isinstance(container.token_verifier, SupabaseJwtVerifier)
    assert isinstance(container.llm, LiteLLMProvider)
    assert isinstance(container.audit, PostgresAuditLogger)
    assert container.llm.models_for("reason")  # models.yaml loaded
