from fastapi.testclient import TestClient

from askmedi.config import DEFAULT_CORS_ORIGIN_REGEX
from askmedi.container import Container
from askmedi.main import create_app


def _preflight(client: TestClient, origin: str):
    return client.options(
        "/me",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )


def test_local_web_app_origin_is_allowed(client):
    response = _preflight(client, "http://localhost:7357")
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:7357"
    assert "authorization" in response.headers["access-control-allow-headers"].lower()


def test_unknown_origin_is_not_allowed(client):
    response = _preflight(client, "https://evil.example.com")
    assert "access-control-allow-origin" not in response.headers


def test_configured_origin_regex_is_used(fake_container: Container):
    client = TestClient(
        create_app(fake_container, cors_origin_regex=r"^https://askmedi\.example$")
    )
    assert _preflight(client, "https://askmedi.example").status_code == 200
    assert "access-control-allow-origin" not in _preflight(
        client, "http://localhost:7357"
    ).headers


def test_default_regex_only_matches_local_hosts():
    import re

    pattern = re.compile(DEFAULT_CORS_ORIGIN_REGEX)
    assert pattern.match("http://localhost:7357")
    assert pattern.match("http://127.0.0.1:8080")
    assert not pattern.match("http://localhost.evil.com")
    assert not pattern.match("https://evil.com")
