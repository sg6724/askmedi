import logging
import time
from collections.abc import Awaitable, Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

import yaml

from askmedi.domain.llm import ChatMessage, LLMResult, LLMUnavailable

logger = logging.getLogger(__name__)

CompletionFn = Callable[..., Awaitable[Any]]


class LiteLLMProvider:
    """Routes each task to an ordered list of models and falls back on any failure."""

    def __init__(
        self,
        task_models: Mapping[str, Sequence[str]],
        completion_fn: CompletionFn | None = None,
        timeout_s: float = 30.0,
    ) -> None:
        self._task_models = {task: list(models) for task, models in task_models.items()}
        self._completion = completion_fn or self._default_completion
        self._timeout_s = timeout_s

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
        for model in self.models_for(task):
            kwargs: dict[str, Any] = {
                "model": model,
                "messages": wire_messages,
                "timeout": self._timeout_s,
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
                errors.append(f"{model}: {exc_type_name}")
                logger.warning("LLM provider error for %s: %s", model, exc_type_name)
                continue
        raise LLMUnavailable("; ".join(errors))

    @staticmethod
    async def _default_completion(**kwargs: Any) -> Any:
        import litellm  # imported lazily: heavy import, and keeps tests fast

        return await litellm.acompletion(**kwargs)
