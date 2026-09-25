"""Grounded web search through Groq's built-in `browser_search` tool (gpt-oss models).

Works on the Groq free tier and does not use the Gemini quota, so it is the first search in the
chain. The model searches the web, reads pages and answers; the search results it used become
the cited sources.
"""

import logging
import re
import time
from collections.abc import Sequence

import httpx

from askmedi.adapters.cooldown import Cooldowns, http_rate_limited
from askmedi.domain.common import Source
from askmedi.domain.search import GroundedText, SearchUnavailable

logger = logging.getLogger(__name__)

API_URL = "https://api.groq.com/openai/v1/chat/completions"
MAX_SOURCES = 8
# The model marks citations like 【2†L6-L7】; the sources are listed separately.
_CITATION_MARKS = re.compile(r"【[^】]*】")


def _bare_model(model: str) -> str:
    return model.removeprefix("groq/")


class GroqWebSearch:
    """Implements the WebSearch port."""

    def __init__(
        self,
        api_key: str,
        *,
        models: Sequence[str],
        timeout_s: float = 25.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._headers = {"Authorization": f"Bearer {api_key}"}
        self._models = [_bare_model(m) for m in models]
        self._timeout_s = timeout_s
        self._transport = transport
        self._cooldowns = Cooldowns()

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText:
        errors: list[str] = []
        async with httpx.AsyncClient(
            timeout=self._timeout_s, headers=self._headers, transport=self._transport
        ) as client:
            for model in self._cooldowns.usable(self._models):
                started = time.perf_counter()
                try:
                    resp = await client.post(
                        API_URL,
                        json={
                            "model": model,
                            "messages": [{"role": "user", "content": question}],
                            "tools": [{"type": "browser_search"}],
                            "tool_choice": "auto",
                            "temperature": 0.2,
                        },
                    )
                    resp.raise_for_status()
                    message = resp.json()["choices"][0]["message"]
                except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError) as exc:
                    if http_rate_limited(exc):
                        self._cooldowns.hit(model, exc.response.text[:500])
                    errors.append(f"{model}: {type(exc).__name__}")
                    logger.warning("groq search failed on %s: %s", model, type(exc).__name__)
                    continue
                text = " ".join(_CITATION_MARKS.sub("", message.get("content") or "").split())
                if not text:
                    errors.append(f"{model}: empty")
                    continue
                return GroundedText(
                    text=text,
                    sources=_sources(message),
                    model=f"groq/{model}",
                    latency_ms=int((time.perf_counter() - started) * 1000),
                )
        raise SearchUnavailable("; ".join(errors) or "no search models configured")


def _sources(message: dict) -> list[Source]:
    seen: set[str] = set()
    sources: list[Source] = []
    for tool in message.get("executed_tools") or []:
        if tool.get("type") != "browser_search":
            continue
        for result in (tool.get("search_results") or {}).get("results") or []:
            url = str(result.get("url") or "")
            if not url.startswith(("https://", "http://")) or url in seen or len(url) > 2000:
                continue
            seen.add(url)
            title = str(result.get("title") or url).strip()[:300]
            sources.append(Source(title=title, url=url))
    return sources[:MAX_SOURCES]
