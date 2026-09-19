import os
import uuid

import psycopg
import pytest

from askmedi.adapters.database import Database
from askmedi.adapters.postgres_audit import PostgresAuditLogger
from askmedi.domain.audit import AuditEvent

pytestmark = pytest.mark.integration
DB_URL = os.environ.get("TEST_DATABASE_URL")
if not DB_URL:
    pytest.skip("TEST_DATABASE_URL not set", allow_module_level=True)


@pytest.fixture
async def users():
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    async with await psycopg.AsyncConnection.connect(DB_URL, autocommit=True) as admin:
        await admin.execute(
            "insert into auth.users (id, email) values (%s, %s), (%s, %s)",
            (a, f"{a}@test.dev", b, f"{b}@test.dev"),
        )
    yield a, b
    async with await psycopg.AsyncConnection.connect(DB_URL, autocommit=True) as admin:
        await admin.execute("delete from auth.users where id in (%s, %s)", (a, b))


@pytest.fixture
async def db():
    database = Database(DB_URL)
    yield database
    await database.close()


async def count_visible(db: Database, user_id: str) -> int:
    async with db.as_user(user_id) as conn:
        cur = await conn.execute("select count(*) from public.audit_events")
        return (await cur.fetchone())[0]


async def test_logged_event_visible_only_to_owner(db, users):
    a, b = users
    await PostgresAuditLogger(db).log(
        AuditEvent(user_id=a, type="answer", payload={"k": "v"}, model="m", latency_ms=12)
    )
    assert await count_visible(db, a) == 1
    assert await count_visible(db, b) == 0


async def test_cannot_write_event_for_another_user(db, users):
    a, b = users
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        async with db.as_user(a) as conn:
            await conn.execute(
                "insert into public.audit_events (user_id, type) values (%s, 'x')", (b,)
            )
