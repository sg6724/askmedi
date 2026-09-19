from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class AuditEvent:
    user_id: str
    type: str
    payload: dict[str, Any] = field(default_factory=dict)
    episode_id: str | None = None
    model: str | None = None
    latency_ms: int | None = None


class AuditLogger(Protocol):
    async def log(self, event: AuditEvent) -> None: ...
