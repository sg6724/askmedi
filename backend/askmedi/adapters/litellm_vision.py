"""Image reading through LiteLLM (Groq vision): the fallback when every Gemini vision model fails.

Images only: Groq's vision models do not take PDFs, so PDFs stay with Gemini.
"""

import base64
import logging
from collections.abc import Awaitable, Callable, Sequence
from typing import Any

from askmedi.domain.llm import BadModelOutput, parse_json_object
from askmedi.domain.search import UnreadableDocument, VisionUnavailable

logger = logging.getLogger(__name__)

Completion = Callable[..., Awaitable[Any]]


async def _litellm_completion(**kwargs: Any) -> Any:
    import litellm  # imported lazily: heavy import, and keeps tests fast

    return await litellm.acompletion(**kwargs)


class LiteLLMVisionReader:
    """Implements the DocumentReader port for images via OpenAI-style image_url messages."""

    def __init__(
        self,
        models: Sequence[str],
        *,
        completion: Completion = _litellm_completion,
        timeout_s: float = 45.0,
    ) -> None:
        self._models = list(models)
        self._completion = completion
        self._timeout_s = timeout_s

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict:
        if not mime_type.startswith("image/"):
            raise VisionUnavailable(f"{mime_type} not supported by fallback vision models")
        url = f"data:{mime_type};base64,{base64.b64encode(data).decode('ascii')}"
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": url}},
                ],
            }
        ]
        errors: list[str] = []
        for model in self._models:
            try:
                resp = await self._completion(
                    model=model, messages=messages, temperature=0, timeout=self._timeout_s
                )
                text = resp.choices[0].message.content if resp.choices else None
            except Exception as exc:  # noqa: BLE001 provider errors vary; fall through to the next
                errors.append(f"{model}: {type(exc).__name__}")
                logger.warning("fallback vision failed on %s: %s", model, type(exc).__name__)
                continue
            if not text or text.isspace():
                errors.append(f"{model}: empty")
                continue
            try:
                return parse_json_object(text)
            except BadModelOutput as exc:
                raise UnreadableDocument(str(exc)) from exc
        raise VisionUnavailable("; ".join(errors) or "no fallback vision models configured")
