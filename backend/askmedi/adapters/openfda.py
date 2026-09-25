"""openFDA drug label API (https://open.fda.gov/apis/drug/label/). Free, no key needed."""

import logging
from typing import Any

import httpx

from askmedi.domain.common import Source
from askmedi.domain.medicine import DrugLabel, DrugLabelUnavailable, us_label_name

logger = logging.getLogger(__name__)

LABEL_URL = "https://api.fda.gov/drug/label.json"
DAILYMED_URL = "https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid={set_id}"


def _join(record: dict[str, Any], *keys: str) -> str:
    parts: list[str] = []
    for key in keys:
        value = record.get(key)
        if isinstance(value, list):
            parts.extend(str(v) for v in value)
        elif value:
            parts.append(str(value))
    return " ".join(" ".join(parts).split())


def parse_label(record: dict[str, Any]) -> DrugLabel:
    openfda = record.get("openfda") or {}
    generic = [str(g) for g in openfda.get("generic_name") or []]
    set_id = record.get("set_id")
    name = (generic[0] if generic else "drug").title()
    url = DAILYMED_URL.format(set_id=set_id) if set_id else "https://open.fda.gov/apis/drug/label/"
    return DrugLabel(
        generic_names=generic,
        brand_names=[str(b) for b in openfda.get("brand_name") or []],
        substances=[str(s) for s in openfda.get("substance_name") or []],
        indications=_join(record, "indications_and_usage", "purpose"),
        warnings=_join(
            record,
            "boxed_warning",
            "warnings",
            "warnings_and_cautions",
            "do_not_use",
            "ask_doctor",
            "ask_doctor_or_pharmacist",
            "stop_use",
        ),
        interactions=_join(record, "drug_interactions"),
        contraindications=_join(record, "contraindications"),
        pregnancy=_join(record, "pregnancy_or_breast_feeding", "pregnancy"),
        inactive_ingredients=_join(record, "inactive_ingredient"),
        source=Source(title=f"U.S. FDA drug label (DailyMed): {name}", url=url),
    )


class OpenFdaLabels:
    """Implements DrugLabelSource."""

    def __init__(
        self, *, timeout_s: float = 10.0, transport: httpx.AsyncBaseTransport | None = None
    ) -> None:
        self._timeout_s = timeout_s
        self._transport = transport

    async def find_label(self, name: str) -> DrugLabel | None:
        term = us_label_name(name).replace('"', "")
        if not term:
            return None
        # Single-ingredient labels first: exact generic name, then any label containing it.
        queries = [
            f'openfda.generic_name.exact:"{term.upper()}"',
            f'openfda.generic_name:"{term}" openfda.substance_name:"{term}"',
            f'openfda.brand_name:"{term}"',
        ]
        async with httpx.AsyncClient(timeout=self._timeout_s, transport=self._transport) as client:
            for query in queries:
                try:
                    resp = await client.get(LABEL_URL, params={"search": query, "limit": 1})
                except httpx.HTTPError as exc:
                    raise DrugLabelUnavailable(type(exc).__name__) from exc
                if resp.status_code == 404:  # openFDA's "no matches"
                    continue
                if resp.status_code >= 400:
                    raise DrugLabelUnavailable(f"HTTP {resp.status_code}")
                results = resp.json().get("results") or []
                if results:
                    return parse_label(results[0])
        return None
