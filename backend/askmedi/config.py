from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_ROOT = Path(__file__).resolve().parent.parent

# Browser origins allowed to call the API (the Flutter web build). Native apps send no
# Origin header and are unaffected. Override with CORS_ORIGIN_REGEX for a hosted web app.
DEFAULT_CORS_ORIGIN_REGEX = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"


class Settings(BaseSettings):
    # hide_input_in_errors: validation errors must never echo env values (DATABASE_URL has a password).
    model_config = SettingsConfigDict(
        env_file=BACKEND_ROOT / ".env", extra="ignore", hide_input_in_errors=True
    )

    supabase_url: str
    database_url: str
    jwt_audience: str = "authenticated"
    models_config_path: Path = BACKEND_ROOT / "config" / "models.yaml"
    cors_origin_regex: str = DEFAULT_CORS_ORIGIN_REGEX

    @property
    def supabase_issuer(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def supabase_jwks_url(self) -> str:
        return f"{self.supabase_issuer}/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    return Settings()
