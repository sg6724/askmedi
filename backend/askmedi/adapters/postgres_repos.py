"""Postgres repositories. Every statement runs as the calling user, so RLS applies."""

from datetime import date
from typing import Any
from urllib.parse import urlparse

from psycopg.types.json import Jsonb

from askmedi.adapters.database import Database
from askmedi.domain.chat import Episode, EpisodeUpdate, Turn
from askmedi.domain.common import Source
from askmedi.domain.profile import Profile
from askmedi.domain.reports import LabValue, StoredReport

_CITATION_SQL = """
    insert into public.citations (user_id, episode_id, turn_id, source_id, title, url)
    values (%s, %s, %s, %s, %s, %s)
"""


def _citation_rows(
    user_id: str, episode_id: str, turn_id: str | None, sources: list[Source]
) -> list[tuple]:
    rows = []
    for s in sources:
        if not s.url.startswith(("http://", "https://")) or len(s.url) > 2000:
            continue
        host = urlparse(s.url).hostname or "web"
        rows.append((user_id, episode_id, turn_id, host[:200], s.title[:300], s.url))
    return rows


async def _create_episode(
    conn: Any, user_id: str, kind: str, language: str, outcome: dict[str, Any] | None = None
) -> str:
    cur = await conn.execute(
        """
        insert into public.episodes (user_id, kind, language, outcome)
        values (%s, %s, %s, %s) returning id
        """,
        (user_id, kind, language, Jsonb(outcome) if outcome is not None else None),
    )
    return str((await cur.fetchone())[0])


class PostgresChatRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def get_episode(self, user_id: str, episode_id: str) -> Episode | None:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                """
                select id, language, symptoms, urgency, followup_count, repeat_flag,
                       red_flag_rule_id
                from public.episodes where id = %s and kind = 'symptom'
                """,
                (episode_id,),
            )
            row = await cur.fetchone()
            if row is None:
                return None
            cur = await conn.execute(
                """
                select role, text_original from public.turns
                where episode_id = %s order by created_at, id
                """,
                (episode_id,),
            )
            turns = [Turn(role=r[0], text=r[1]) for r in await cur.fetchall()]
        return Episode(
            id=str(row[0]),
            language=row[1],
            symptoms=list(row[2] or []),
            urgency=row[3],
            followup_count=row[4],
            repeat_flag=row[5],
            red_flag_rule_id=row[6],
            turns=turns,
        )

    async def create_episode(self, user_id: str, language: str) -> str:
        async with self._db.as_user(user_id) as conn:
            return await _create_episode(conn, user_id, "symptom", language)

    async def add_turn(
        self,
        user_id: str,
        episode_id: str,
        role: str,
        text: str,
        *,
        normalised: str | None = None,
        lang: str | None = None,
    ) -> str:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                """
                insert into public.turns (user_id, episode_id, role, text_original,
                                          text_normalised, lang)
                values (%s, %s, %s, %s, %s, %s) returning id
                """,
                (user_id, episode_id, role, text, normalised, lang),
            )
            return str((await cur.fetchone())[0])

    async def update_episode(self, user_id: str, episode_id: str, update: EpisodeUpdate) -> None:
        sets: list[str] = []
        params: list[Any] = []
        for column in ("symptoms", "urgency", "followup_count", "red_flag_rule_id", "repeat_flag"):
            value = getattr(update, column)
            if value is not None:
                sets.append(f"{column} = %s")
                params.append(value)
        if update.outcome is not None:
            sets.append("outcome = %s")
            params.append(Jsonb(update.outcome))
        if not sets:
            return
        async with self._db.as_user(user_id) as conn:
            await conn.execute(
                f"update public.episodes set {', '.join(sets)} where id = %s",
                (*params, episode_id),
            )

    async def add_citations(
        self, user_id: str, episode_id: str, turn_id: str | None, sources: list[Source]
    ) -> None:
        rows = _citation_rows(user_id, episode_id, turn_id, sources)
        if not rows:
            return
        async with self._db.as_user(user_id) as conn, conn.cursor() as cur:
            await cur.executemany(_CITATION_SQL, rows)

    async def count_recent_similar(
        self, user_id: str, symptoms: list[str], *, days: int, exclude_episode_id: str
    ) -> int:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                """
                select count(*) from public.episodes
                where kind = 'symptom' and id <> %s
                  and started_at > now() - make_interval(days => %s)
                  and symptoms && %s::text[]
                """,
                (exclude_episode_id, days, symptoms),
            )
            return int((await cur.fetchone())[0])


class PostgresProfileRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def get_profile(self, user_id: str) -> Profile:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                "select birth_year, sex, pregnant from public.profiles where user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()
            conditions = await conn.execute("select name from public.health_conditions")
            conditions_rows = await conditions.fetchall()
            medicines = await conn.execute("select salt from public.user_medicines")
            medicine_rows = await medicines.fetchall()
            allergies = await conn.execute("select substance from public.allergies")
            allergy_rows = await allergies.fetchall()
        return Profile(
            birth_year=row[0] if row else None,
            sex=row[1] if row else None,
            pregnant=row[2] if row else None,
            conditions=[r[0] for r in conditions_rows],
            medicines=[r[0] for r in medicine_rows],
            allergies=[r[0] for r in allergy_rows],
        )


class PostgresMedicineRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def save_lookup(
        self,
        user_id: str,
        *,
        language: str,
        query: str,
        brand: str | None,
        salts: list[dict[str, Any]],
        info: dict[str, Any],
        flags: list[dict[str, str]],
        sources: list[Source],
    ) -> str:
        async with self._db.as_user(user_id) as conn:
            episode_id = await _create_episode(
                conn, user_id, "medicine", language, outcome={"type": "medicine", "name": query}
            )
            cur = await conn.execute(
                """
                insert into public.medicine_lookups
                  (user_id, episode_id, query, brand, salts, info, flags)
                values (%s, %s, %s, %s, %s, %s, %s) returning id
                """,
                (
                    user_id,
                    episode_id,
                    query,
                    brand[:200] if brand else None,
                    Jsonb(salts),
                    Jsonb({**info, "sources": [s.to_dict() for s in sources]}),
                    Jsonb(flags),
                ),
            )
            lookup_id = str((await cur.fetchone())[0])
            rows = _citation_rows(user_id, episode_id, None, sources)
            if rows:
                async with conn.cursor() as c:
                    await c.executemany(_CITATION_SQL, rows)
        return lookup_id


_VALUE_SQL = """
    insert into public.report_values
      (user_id, report_id, test_name, value, unit, ref_low, ref_high, ref_text, status, report_date)
    values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
"""


def _value_rows(
    user_id: str, report_id: str, values: list[LabValue], report_date: date | None
) -> list[tuple]:
    return [
        (
            user_id,
            report_id,
            v.test_name,
            v.value,
            v.unit,
            v.ref_low,
            v.ref_high,
            v.ref_text,
            v.status,
            report_date,
        )
        for v in values
    ]


class PostgresReportRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def create_draft(
        self, user_id: str, report_date: date | None, lab: str | None, values: list[LabValue]
    ) -> str:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                """
                insert into public.reports (user_id, report_date, lab, status)
                values (%s, %s, %s, 'draft') returning id
                """,
                (user_id, report_date, lab),
            )
            report_id = str((await cur.fetchone())[0])
            async with conn.cursor() as c:
                await c.executemany(
                    _VALUE_SQL, _value_rows(user_id, report_id, values, report_date)
                )
        return report_id

    async def get(self, user_id: str, report_id: str) -> StoredReport | None:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                "select id, report_date, lab, status from public.reports where id = %s",
                (report_id,),
            )
            row = await cur.fetchone()
        if row is None:
            return None
        return StoredReport(id=str(row[0]), report_date=row[1], lab=row[2], status=row[3])

    async def confirm(
        self,
        user_id: str,
        report_id: str,
        values: list[LabValue],
        summary: dict[str, Any],
        language: str,
        sources: list[Source],
    ) -> str:
        async with self._db.as_user(user_id) as conn:
            cur = await conn.execute(
                "select report_date, episode_id from public.reports where id = %s", (report_id,)
            )
            report_date, episode_id = await cur.fetchone()
            if episode_id is None:
                episode_id = await _create_episode(
                    conn, user_id, "report", language, outcome={"type": "report"}
                )
            episode_id = str(episode_id)
            await conn.execute(
                "delete from public.report_values where report_id = %s", (report_id,)
            )
            async with conn.cursor() as c:
                await c.executemany(
                    _VALUE_SQL, _value_rows(user_id, report_id, values, report_date)
                )
            await conn.execute(
                """
                update public.reports set status = 'confirmed', summary = %s, episode_id = %s
                where id = %s
                """,
                (
                    Jsonb({**summary, "sources": [s.to_dict() for s in sources]}),
                    episode_id,
                    report_id,
                ),
            )
            rows = _citation_rows(user_id, episode_id, None, sources)
            if rows:
                async with conn.cursor() as c:
                    await c.executemany(_CITATION_SQL, rows)
        return episode_id
