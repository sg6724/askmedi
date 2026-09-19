"""Live check that every configured model answers. Usage: uv run python scripts/llm_smoke.py"""
import asyncio

from askmedi.adapters.litellm_provider import LiteLLMProvider
from askmedi.config import BACKEND_ROOT
from askmedi.domain.llm import ChatMessage


async def main() -> None:
    provider = LiteLLMProvider.from_yaml(BACKEND_ROOT / "config" / "models.yaml")
    prompt = [ChatMessage(role="user", content="Reply with exactly: OK")]
    for task in ("normalise", "reason", "respond", "vision"):
        for model in provider.models_for(task):
            single = LiteLLMProvider({task: [model]})
            try:
                result = await single.complete(task, prompt)
                print(f"PASS {task:10} {model:55} {result.latency_ms} ms -> {result.text!r}")
            except Exception as exc:  # noqa: BLE001
                print(f"FAIL {task:10} {model:55} {exc}")


if __name__ == "__main__":
    asyncio.run(main())
