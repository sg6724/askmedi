"""Symptom chat: persistence port and episode state."""

from dataclasses import dataclass, field
from typing import Any, Protocol

from askmedi.domain.common import Source

MAX_FOLLOWUPS = 3


@dataclass(frozen=True)
class Turn:
    role: str
    text: str


@dataclass(frozen=True)
class Episode:
    id: str
    language: str
    symptoms: list[str] = field(default_factory=list)
    urgency: str | None = None
    followup_count: int = 0
    repeat_flag: bool = False
    red_flag_rule_id: str | None = None
    turns: list[Turn] = field(default_factory=list)


@dataclass
class EpisodeUpdate:
    symptoms: list[str] | None = None
    urgency: str | None = None
    followup_count: int | None = None
    outcome: dict[str, Any] | None = None
    red_flag_rule_id: str | None = None
    repeat_flag: bool | None = None


class ChatRepository(Protocol):
    async def get_episode(self, user_id: str, episode_id: str) -> Episode | None: ...

    async def create_episode(self, user_id: str, language: str) -> str: ...

    async def add_turn(
        self,
        user_id: str,
        episode_id: str,
        role: str,
        text: str,
        *,
        normalised: str | None = None,
        lang: str | None = None,
    ) -> str: ...

    async def update_episode(
        self, user_id: str, episode_id: str, update: EpisodeUpdate
    ) -> None: ...

    async def add_citations(
        self, user_id: str, episode_id: str, turn_id: str | None, sources: list[Source]
    ) -> None: ...

    async def count_recent_similar(
        self, user_id: str, symptoms: list[str], *, days: int, exclude_episode_id: str
    ) -> int: ...
