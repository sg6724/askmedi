from collections.abc import Sequence
from dataclasses import dataclass
from typing import Literal, Protocol

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
