from types import SimpleNamespace

import pytest

from askmedi.adapters.litellm_provider import LiteLLMProvider
from askmedi.domain.llm import ChatMessage, LLMUnavailable

MSGS = [ChatMessage(role="user", content="hello")]


def response(text: str):
    return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=text))])


class ScriptedCompletion:
    """Fails for models listed in `failing`, succeeds otherwise; records calls."""

    def __init__(self, failing=()):
        self.failing = set(failing)
        self.calls: list[dict] = []

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        if kwargs["model"] in self.failing:
            raise RuntimeError(f"429 from {kwargs['model']}")
        return response(f"answer from {kwargs['model']}")


async def test_uses_primary_model_when_it_succeeds():
    fn = ScriptedCompletion()
    provider = LiteLLMProvider({"reason": ["gemini/a", "groq/b"]}, completion_fn=fn)
    result = await provider.complete("reason", MSGS)
    assert result.text == "answer from gemini/a"
    assert result.model == "gemini/a"
    assert [c["model"] for c in fn.calls] == ["gemini/a"]
    assert fn.calls[0]["messages"] == [{"role": "user", "content": "hello"}]


async def test_falls_back_when_primary_fails():
    fn = ScriptedCompletion(failing={"gemini/a"})
    provider = LiteLLMProvider({"reason": ["gemini/a", "groq/b"]}, completion_fn=fn)
    result = await provider.complete("reason", MSGS)
    assert result.model == "groq/b"


async def test_raises_when_all_models_fail():
    fn = ScriptedCompletion(failing={"gemini/a", "groq/b"})
    provider = LiteLLMProvider({"reason": ["gemini/a", "groq/b"]}, completion_fn=fn)
    with pytest.raises(LLMUnavailable) as exc:
        await provider.complete("reason", MSGS)
    assert "gemini/a" in str(exc.value) and "groq/b" in str(exc.value)


async def test_unknown_task_raises_key_error():
    provider = LiteLLMProvider({"reason": ["gemini/a"]}, completion_fn=ScriptedCompletion())
    with pytest.raises(KeyError):
        await provider.complete("nope", MSGS)


async def test_json_mode_requests_json_object():
    fn = ScriptedCompletion()
    provider = LiteLLMProvider({"normalise": ["groq/x"]}, completion_fn=fn)
    await provider.complete("normalise", MSGS, json_mode=True)
    assert fn.calls[0]["response_format"] == {"type": "json_object"}


def test_from_yaml_loads_task_models(tmp_path):
    cfg = tmp_path / "models.yaml"
    cfg.write_text("tasks:\n  reason: [gemini/a, groq/b]\n", encoding="utf-8")
    provider = LiteLLMProvider.from_yaml(cfg)
    assert provider.models_for("reason") == ["gemini/a", "groq/b"]
