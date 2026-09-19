from psycopg.types.json import Jsonb

from askmedi.adapters.database import Database
from askmedi.domain.audit import AuditEvent


class PostgresAuditLogger:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def log(self, event: AuditEvent) -> None:
        async with self._db.as_user(event.user_id) as conn:
            await conn.execute(
                """
                insert into public.audit_events
                  (user_id, episode_id, type, payload, model, latency_ms)
                values (%s, %s, %s, %s, %s, %s)
                """,
                (
                    event.user_id,
                    event.episode_id,
                    event.type,
                    Jsonb(event.payload),
                    event.model,
                    event.latency_ms,
                ),
            )
