"""Skips a model for a while after it answers 429 (free-tier rate limits and daily quotas)."""

import time
from collections.abc import Callable, Sequence

import httpx

MINUTE_COOLDOWN_S = 60.0
DAILY_COOLDOWN_S = 15 * 60.0


def http_rate_limited(exc: Exception) -> bool:
    return isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code == 429


class Cooldowns:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._until: dict[str, float] = {}

    def usable(self, models: Sequence[str]) -> list[str]:
        """Models not cooling down, in order; all of them if every one is cooling down."""
        now = self._clock()
        ready = [m for m in models if self._until.get(m, 0.0) <= now]
        return ready or list(models)

    def hit(self, model: str, detail: str = "") -> None:
        text = detail.lower()
        daily = any(k in text for k in ("per day", "tpd", "quota", "rpd"))
        self._until[model] = self._clock() + (DAILY_COOLDOWN_S if daily else MINUTE_COOLDOWN_S)
