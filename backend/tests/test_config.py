import pytest
from pydantic import ValidationError

from askmedi.config import Settings


def test_validation_error_does_not_echo_input_secrets(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(ValidationError) as excinfo:
        # supabase_url is missing, so validation fails; the input dict must not be echoed.
        Settings(_env_file=None, database_url="postgresql://u:Hunter2@db:5432/p")
    assert "supabase_url" in str(excinfo.value)
    assert "Hunter2" not in str(excinfo.value)
