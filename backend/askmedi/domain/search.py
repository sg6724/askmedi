from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Protocol

from askmedi.domain.common import Source


@dataclass(frozen=True)
class GroundedText:
    text: str
    sources: list[Source] = field(default_factory=list)
    model: str | None = None
    latency_ms: int | None = None


class SearchUnavailable(Exception):
    """The web-search provider failed for every configured model."""


class WebSearch(Protocol):
    """Answers a question using a live web search and returns the sources used.

    `keywords` are short English terms (symptoms, medicine or test names) for search backends
    that need a keyword query rather than a natural-language question.
    """

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText: ...


class DocumentReader(Protocol):
    """Reads an image or PDF with a vision model and returns the parsed JSON object."""

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict: ...


class VisionUnavailable(Exception):
    """Every configured vision model failed."""


class UnreadableDocument(Exception):
    """The vision model answered but returned nothing parseable."""
