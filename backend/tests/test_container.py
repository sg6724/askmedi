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


def test_build_container_wires_feature_services(monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    settings = Settings(
        _env_file=None,
        supabase_url="https://proj.supabase.co",
        database_url="postgresql://u:p@localhost:5432/db",
    )
    container = build_container(settings)
    for service in ("chat", "medicine", "reports", "hospitals", "voice"):
        assert getattr(container, service) is not None, service
    assert container.voice.available is False  # no key -> 503 voice_unavailable
    assert container.llm.models_for("search")


def test_voice_is_available_when_key_is_set():
    settings = Settings(
        _env_file=None,
        supabase_url="https://proj.supabase.co",
        database_url="postgresql://u:p@localhost:5432/db",
        elevenlabs_api_key="k",
    )
    assert build_container(settings).voice.available is True
