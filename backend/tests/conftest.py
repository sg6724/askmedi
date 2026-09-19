import asyncio
import selectors
import sys
from dataclasses import dataclass, field

import pytest
from fastapi.testclient import TestClient

from askmedi.container import Container
from askmedi.domain.audit import AuditEvent
from askmedi.domain.auth import AuthUser, InvalidToken
from askmedi.domain.llm import LLMResult
from askmedi.main import create_app


class FakeVerifier:
    """Accepts 'good-token' as user-1; rejects everything else."""

    def verify(self, token: str) -> AuthUser:
        if token != "good-token":
            raise InvalidToken("bad token")
        return AuthUser(user_id="user-1", email="u1@test.dev", claims={"sub": "user-1"})


class FakeLLM:
    async def complete(self, task, messages, *, json_mode=False):
        return LLMResult(text="ok", model="fake/model", latency_ms=1)


@dataclass
class FakeAudit:
    events: list[AuditEvent] = field(default_factory=list)

    async def log(self, event: AuditEvent) -> None:
        self.events.append(event)


@pytest.fixture
def fake_container() -> Container:
    return Container(token_verifier=FakeVerifier(), llm=FakeLLM(), audit=FakeAudit())


@pytest.fixture
def client(fake_container: Container) -> TestClient:
    return TestClient(create_app(fake_container))


if sys.platform == "win32":
    # psycopg async cannot run on Windows' default ProactorEventLoop, so use a selector loop.
    # Defined ONLY on win32: pytest-asyncio 1.4.0 raises UsageError if any hook implementation
    # exists and returns None, so the hook must not exist at all on other platforms.
    def pytest_asyncio_loop_factories(config, item):
        return {"selector": lambda: asyncio.SelectorEventLoop(selectors.SelectSelector())}
