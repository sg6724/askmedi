"""Small helpers shared by the use-case services."""

import logging
from typing import Any

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.common import Source, UpstreamUnavailable
from askmedi.domain.llm import (
    BadModelOutput,
    ChatMessage,
    LLMProvider,
    LLMResult,
    LLMUnavailable,
    parse_json_object,
)
from askmedi.domain.search import GroundedText, SearchUnavailable, WebSearch
from askmedi.safety.output_guard import OutputGuard
from askmedi.services import prompts

logger = logging.getLogger(__name__)


async def complete_json(
    llm: LLMProvider, task: str, messages: list[tuple[str, str]]
) -> tuple[dict[str, Any], LLMResult]:
    """One JSON-mode completion; retries once if the output is not a JSON object.

    Raises UpstreamUnavailable("llm_unavailable") when every model fails.
    """
    wire = [ChatMessage(role=role, content=content) for role, content in messages]  # type: ignore[arg-type]
    last_error: Exception | None = None
    for _ in range(2):
        try:
            result = await llm.complete(task, wire, json_mode=True)
        except LLMUnavailable as exc:
            raise UpstreamUnavailable("llm_unavailable") from exc
        try:
            return parse_json_object(result.text), result
        except BadModelOutput as exc:
            last_error = exc
    logger.warning("model returned no usable JSON for task %s: %s", task, last_error)
    raise UpstreamUnavailable("llm_unavailable")


async def research(
    search: WebSearch, question: str, keywords: list[str] | None = None
) -> GroundedText:
    """Live web search; on failure returns empty notes so callers can answer more cautiously."""
    try:
        return await search.research(question, keywords or [])
    except SearchUnavailable as exc:
        logger.warning("web search unavailable: %s", exc)
        return GroundedText(text="", sources=[])


async def guarded_json(
    llm: LLMProvider,
    guard: OutputGuard,
    task: str,
    messages: list[tuple[str, str]],
) -> tuple[dict[str, Any] | None, list[str], LLMResult]:
    """Model JSON that passes the OutputGuard, after at most one repair.

    Returns (data or None if still unsafe, violations of the first draft, last LLM result).
    """
    data, result = await complete_json(llm, task, messages)
    first = guard.violations(data)
    if not first:
        return data, [], result
    repaired, result = await complete_json(llm, task, prompts.repair_messages(data, first))
    if guard.violations(repaired):
        return None, first, result
    return repaired, first, result


async def safe_audit(audit: AuditLogger, event: AuditEvent) -> None:
    """Audit logging must never break the user's request."""
    try:
        await audit.log(event)
    except Exception:
        logger.exception("audit log failed for event %s", event.type)


def str_list(value: Any, limit: int, item_limit: int = 300) -> list[str]:
    if not isinstance(value, list):
        return []
    out = [str(v).strip()[:item_limit] for v in value if isinstance(v, str | int | float)]
    return [v for v in out if v][:limit]


def dedupe_sources(sources: list[Source], limit: int = 8) -> list[Source]:
    seen: set[str] = set()
    out: list[Source] = []
    for s in sources:
        if s.url in seen:
            continue
        seen.add(s.url)
        out.append(s)
    return out[:limit]
