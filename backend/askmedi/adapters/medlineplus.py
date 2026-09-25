"""MedlinePlus health-topic search (https://medlineplus.gov/about/developers/webservices/).

Free, no key, public-domain content. Used as the live-search fallback when Gemini grounding is
unavailable (e.g. the free-tier daily quota is used up).
"""

import html
import logging
import re
import time
import xml.etree.ElementTree as ET
from collections.abc import Sequence

import httpx

from askmedi.domain.common import Source
from askmedi.domain.search import GroundedText, SearchUnavailable

logger = logging.getLogger(__name__)

SEARCH_URL = "https://wsearch.nlm.nih.gov/ws/query"
_TAGS = re.compile(r"<[^>]+>")


def _plain(text: str) -> str:
    return " ".join(_TAGS.sub(" ", html.unescape(text or "")).split())


def parse_results(xml_text: str) -> list[tuple[str, str, str]]:
    """[(title, url, summary)] from a wsearch response."""
    root = ET.fromstring(xml_text)
    out = []
    for doc in root.iter("document"):
        fields = {c.get("name"): c.text or "" for c in doc.findall("content")}
        url = doc.get("url") or ""
        title = _plain(fields.get("title", ""))
        if url.startswith("https://") and title:
            out.append((title, url, _plain(fields.get("FullSummary", ""))))
    return out


class MedlinePlusSearch:
    """Implements WebSearch using keyword queries (one query per keyword, best hits first)."""

    def __init__(
        self,
        *,
        per_keyword: int = 2,
        max_keywords: int = 3,
        timeout_s: float = 10.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._per_keyword = per_keyword
        self._max_keywords = max_keywords
        self._timeout_s = timeout_s
        self._transport = transport

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText:
        terms = [k.strip() for k in keywords if k and k.strip()][: self._max_keywords]
        if not terms:
            raise SearchUnavailable("medlineplus: no keywords")
        started = time.perf_counter()
        hits: dict[str, tuple[str, str]] = {}
        try:
            async with httpx.AsyncClient(timeout=self._timeout_s, transport=self._transport) as c:
                for term in terms:
                    resp = await c.get(
                        SEARCH_URL,
                        params={"db": "healthTopics", "term": term, "retmax": self._per_keyword},
                    )
                    resp.raise_for_status()
                    for title, url, summary in parse_results(resp.text):
                        hits.setdefault(url, (title, summary))
        except (httpx.HTTPError, ET.ParseError) as exc:
            raise SearchUnavailable(f"medlineplus: {type(exc).__name__}") from exc
        if not hits:
            raise SearchUnavailable("medlineplus: no results")
        notes = "\n\n".join(
            f"{title} (MedlinePlus): {summary[:1200]}" for title, summary in hits.values()
        )
        return GroundedText(
            text=notes,
            sources=[Source(f"MedlinePlus: {title}", url) for url, (title, _) in hits.items()],
            model="medlineplus",
            latency_ms=int((time.perf_counter() - started) * 1000),
        )
