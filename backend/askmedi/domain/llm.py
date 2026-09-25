import json
import re
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any, Literal, Protocol

Role = Literal["system", "user", "assistant"]


@dataclass(frozen=True)
class ChatMessage:
    role: Role
    content: str


@dataclass(frozen=True)
class LLMResult:
    text: str
    model: str
    latency_ms: int


class LLMUnavailable(Exception):
    """Raised when every model configured for a task failed."""


class LLMProvider(Protocol):
    async def complete(
        self, task: str, messages: Sequence[ChatMessage], *, json_mode: bool = False
    ) -> LLMResult: ...


_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


class BadModelOutput(Exception):
    """The model did not return a JSON object."""


def parse_json_object(text: str) -> dict[str, Any]:
    """Parses a JSON object from model text, tolerating code fences and surrounding prose."""
    cleaned = _FENCE.sub("", text.strip())
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError:
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start < 0 or end <= start:
            raise BadModelOutput("no JSON object in model output") from None
        try:
            data = json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError as exc:
            raise BadModelOutput("malformed JSON in model output") from exc
    if not isinstance(data, dict):
        raise BadModelOutput("model output is not a JSON object")
    return data
