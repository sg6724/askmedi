"""Gemini REST adapter: Google-Search-grounded research and vision JSON extraction.

Grounding cannot be combined with JSON response mode, so research returns plain text plus the
grounding sources; callers structure it with a separate JSON call.
"""

import asyncio
import base64
import logging
import time
from collections.abc import Sequence
from typing import Any

import httpx

from askmedi.domain.common import Source
from askmedi.domain.llm import BadModelOutput, parse_json_object
from askmedi.domain.search import (
    GroundedText,
    SearchUnavailable,
    UnreadableDocument,
    VisionUnavailable,
)

logger = logging.getLogger(__name__)

API_BASE = "https://generativelanguage.googleapis.com/v1beta"
REDIRECT_HOST = "vertexaisearch.cloud.google.com"


def _bare_model(model: str) -> str:
    """'gemini/gemini-2.5-flash' (LiteLLM style) -> 'gemini-2.5-flash'."""
    return model.split("/", 1)[1] if model.startswith("gemini/") else model


def _candidate_text(body: dict[str, Any]) -> str:
    candidates = body.get("candidates") or []
    if not candidates:
        return ""
    parts = (candidates[0].get("content") or {}).get("parts") or []
    return "".join(p.get("text", "") for p in parts if isinstance(p, dict)).strip()


def grounding_sources(body: dict[str, Any]) -> list[Source]:
    candidates = body.get("candidates") or []
    if not candidates:
        return []
    chunks = (candidates[0].get("groundingMetadata") or {}).get("groundingChunks") or []
    sources: list[Source] = []
    seen: set[str] = set()
    for chunk in chunks:
        web = chunk.get("web") if isinstance(chunk, dict) else None
        if not web or not str(web.get("uri", "")).startswith("http"):
            continue
        uri = web["uri"]
        if uri in seen:
            continue
        seen.add(uri)
        sources.append(Source(title=str(web.get("title") or uri)[:300], url=uri[:2000]))
    return sources


class GeminiClient:
    """Implements the WebSearch and DocumentReader ports."""

    def __init__(
        self,
        api_key: str,
        *,
        search_models: Sequence[str],
        vision_models: Sequence[str],
        timeout_s: float = 25.0,
        transport: httpx.AsyncBaseTransport | None = None,
        resolve_redirects: bool = True,
    ) -> None:
        self._api_key = api_key
        self._search_models = [_bare_model(m) for m in search_models]
        self._vision_models = [_bare_model(m) for m in vision_models if m.startswith("gemini")]
        self._timeout_s = timeout_s
        self._transport = transport
        self._resolve_redirects = resolve_redirects

    def _client(self, timeout: float | None = None) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=timeout or self._timeout_s, transport=self._transport)

    async def _generate(
        self, client: httpx.AsyncClient, model: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        resp = await client.post(
            f"{API_BASE}/models/{model}:generateContent",
            headers={"x-goog-api-key": self._api_key},
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()

    # ---------------------------------------------------------------- WebSearch

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText:
        payload = {
            "contents": [{"role": "user", "parts": [{"text": question}]}],
            "tools": [{"google_search": {}}],
        }
        errors: list[str] = []
        async with self._client() as client:
            for model in self._search_models:
                started = time.perf_counter()
                try:
                    body = await self._generate(client, model, payload)
                except (httpx.HTTPError, ValueError) as exc:
                    errors.append(f"{model}: {type(exc).__name__}")
                    logger.warning("grounded search failed on %s: %s", model, type(exc).__name__)
                    continue
                text = _candidate_text(body)
                if not text:
                    errors.append(f"{model}: empty")
                    continue
                sources = grounding_sources(body)
                if self._resolve_redirects:
                    sources = await self._resolve(client, sources)
                return GroundedText(
                    text=text,
                    sources=sources,
                    model=f"gemini/{model}",
                    latency_ms=int((time.perf_counter() - started) * 1000),
                )
        raise SearchUnavailable("; ".join(errors) or "no search models configured")

    async def _resolve(self, client: httpx.AsyncClient, sources: list[Source]) -> list[Source]:
        """Grounding URLs are Google redirect links; resolve them to the publisher's URL."""

        async def one(source: Source) -> Source:
            if REDIRECT_HOST not in source.url:
                return source
            try:
                resp = await client.head(source.url, follow_redirects=False, timeout=4.0)
                location = resp.headers.get("location", "")
                if resp.is_redirect and location.startswith("http") and len(location) <= 2000:
                    return Source(title=source.title, url=location)
            except httpx.HTTPError:
                pass
            return source

        return list(await asyncio.gather(*(one(s) for s in sources)))

    # ---------------------------------------------------------------- DocumentReader

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict:
        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "inline_data": {
                                "mime_type": mime_type,
                                "data": base64.b64encode(data).decode("ascii"),
                            }
                        },
                        {"text": prompt},
                    ],
                }
            ],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0},
        }
        errors: list[str] = []
        async with self._client(timeout=25.0) as client:
            for model in self._vision_models:
                try:
                    body = await self._generate(client, model, payload)
                except (httpx.HTTPError, ValueError) as exc:
                    errors.append(f"{model}: {type(exc).__name__}")
                    logger.warning("vision failed on %s: %s", model, type(exc).__name__)
                    continue
                text = _candidate_text(body)
                if not text:
                    errors.append(f"{model}: empty")
                    continue
                try:
                    return parse_json_object(text)
                except BadModelOutput as exc:
                    raise UnreadableDocument(str(exc)) from exc
        raise VisionUnavailable("; ".join(errors) or "no vision models configured")
