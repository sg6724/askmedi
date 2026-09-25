import logging
import time
from collections.abc import Awaitable, Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

import yaml

from askmedi.domain.llm import ChatMessage, LLMResult, LLMUnavailable

logger = logging.getLogger(__name__)

# After a 429, skip the model for a while instead of paying a failed round trip on every
# request: a minute for per-minute limits, longer for daily quotas (free tiers).
from askmedi.adapters.cooldown import DAILY_COOLDOWN_S, MINUTE_COOLDOWN_S


def is_rate_limit(exc: Exception) -> bool:
    return getattr(exc, "status_code", None) == 429 or type(exc).__name__ == "RateLimitError"


CompletionFn = Callable[..., Awaitable[Any]]


class LiteLLMProvider:
    """Routes each task to an ordered list of models and falls back on any failure."""

    def __init__(
        self,
        task_models: Mapping[str, Sequence[str]],
        completion_fn: CompletionFn | None = None,
        timeout_s: float = 20.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._task_models = {task: list(models) for task, models in task_models.items()}
        self._completion = completion_fn or self._default_completion
        self._timeout_s = timeout_s
        self._clock = clock
        # model -> time until which it is skipped after a rate limit (free-tier quotas).
        self._cooling: dict[str, float] = {}

    def _usable(self, models: Sequence[str]) -> list[str]:
        now = self._clock()
        ready = [m for m in models if self._cooling.get(m, 0.0) <= now]
        # If every model is cooling down, try them all rather than fail without asking.
        return ready or list(models)

    def _cool_down(self, model: str, exc: Exception) -> None:
        daily = any(k in str(exc).lower() for k in ("per day", "tpd", "quota"))
        self._cooling[model] = self._clock() + (DAILY_COOLDOWN_S if daily else MINUTE_COOLDOWN_S)

    @classmethod
    def from_yaml(cls, path: str | Path) -> "LiteLLMProvider":
        data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
        return cls(data["tasks"])

    def models_for(self, task: str) -> list[str]:
        if task not in self._task_models:
            raise KeyError(f"Unknown LLM task {task!r}")
        return self._task_models[task]

    async def complete(
        self, task: str, messages: Sequence[ChatMessage], *, json_mode: bool = False
    ) -> LLMResult:
        errors: list[str] = []
        wire_messages = [{"role": m.role, "content": m.content} for m in messages]
        for model in self._usable(self.models_for(task)):
            kwargs: dict[str, Any] = {
                "model": model,
                "messages": wire_messages,
                "timeout": self._timeout_s,
                # No hidden retries: on a 429 the SDK would otherwise wait for the provider's
                # retry-after (often 30-40 s on free tiers). The next model is tried instead.
                "num_retries": 0,
                "max_retries": 0,
            }
            if json_mode:
                kwargs["response_format"] = {"type": "json_object"}
            started = time.perf_counter()
            try:
                resp = await self._completion(**kwargs)
                # Parse response, treating empty/malformed as failures
                if not resp.choices:
                    errors.append(f"{model}: empty response")
                    continue
                text = resp.choices[0].message.content
                if text is None or not text or text.isspace():
                    errors.append(f"{model}: empty response")
                    continue
                latency = int((time.perf_counter() - started) * 1000)
                return LLMResult(text=text, model=model, latency_ms=latency)
            except Exception as exc:  # noqa: BLE001 provider errors vary widely; catch all to enable fallback
                exc_type_name = type(exc).__name__
                if is_rate_limit(exc):
                    self._cool_down(model, exc)
                errors.append(f"{model}: {exc_type_name}")
                logger.warning("LLM provider error for %s: %s", model, exc_type_name)
                continue
        raise LLMUnavailable("; ".join(errors))

    @staticmethod
    async def _default_completion(**kwargs: Any) -> Any:
        import litellm  # imported lazily: heavy import, and keeps tests fast

        return await litellm.acompletion(**kwargs)
