import asyncio
import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from psycopg import AsyncConnection
from psycopg_pool import AsyncConnectionPool


class Database:
    """Postgres access where every unit of work runs as the calling user (RLS applies).

    Event-loop affinity: the pool (and the internal asyncio.Lock) is bound to the event loop
    on which the first `as_user()` call runs. The application must run on a single long-lived
    loop (or construct one `Database` per loop). Never share an instance across loops or
    across separate `asyncio.run` calls, and await `close()` on that same loop.
    """

    def __init__(self, conninfo: str, max_size: int = 5) -> None:
        # prepare_threshold=None: required by Supabase's transaction pooler (no prepared stmts)
        self._pool = AsyncConnectionPool(
            conninfo,
            min_size=1,
            max_size=max_size,
            open=False,
            kwargs={"prepare_threshold": None},
        )
        self._opened = False
        self._lock = asyncio.Lock()

    async def _ensure_open(self) -> None:
        if self._opened:
            return
        async with self._lock:
            if not self._opened:
                await self._pool.open()
                self._opened = True

    @asynccontextmanager
    async def as_user(self, user_id: str) -> AsyncIterator[AsyncConnection]:
        await self._ensure_open()
        claims = json.dumps({"sub": user_id, "role": "authenticated"})
        async with self._pool.connection() as conn, conn.transaction():
            await conn.execute("select set_config('request.jwt.claims', %s, true)", (claims,))
            await conn.execute("set local role authenticated")
            yield conn

    async def close(self) -> None:
        if self._opened:
            await self._pool.close()
            self._opened = False
