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


class MalformedCompletion:
    """Returns malformed responses or None content; succeeds only for specified models."""

    def __init__(self, working_model=None):
        self.working_model = working_model
        self.calls: list[dict] = []

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        model = kwargs["model"]
        if model == self.working_model:
            return response(f"answer from {model}")
        # Return malformed response
        if model == "gemini/empty-choices":
            return SimpleNamespace(choices=[])
        if model == "gemini/none-content":
            return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=None))])
        if "empty-content" in model:
            return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=""))])
        # Fallback: return working response
        return response(f"answer from {model}")


async def test_empty_choices_triggers_fallback():
    """Empty choices list should trigger fallback to next model."""
    fn = MalformedCompletion(working_model="groq/b")
    provider = LiteLLMProvider({"reason": ["gemini/empty-choices", "groq/b"]}, completion_fn=fn)
    result = await provider.complete("reason", MSGS)
    assert result.model == "groq/b"
    assert result.text == "answer from groq/b"


async def test_none_content_triggers_fallback():
    """None content should trigger fallback to next model."""
    fn = MalformedCompletion(working_model="groq/b")
    provider = LiteLLMProvider({"reason": ["gemini/none-content", "groq/b"]}, completion_fn=fn)
    result = await provider.complete("reason", MSGS)
    assert result.model == "groq/b"
    assert result.text == "answer from groq/b"


async def test_all_models_empty_content_raises_unavailable():
    """When all models return empty content, should raise LLMUnavailable with model names."""
    fn = MalformedCompletion()
    provider = LiteLLMProvider(
        {"reason": ["gemini/empty-content", "groq/empty-content"]}, completion_fn=fn
    )
    with pytest.raises(LLMUnavailable) as exc:
        await provider.complete("reason", MSGS)
    exc_str = str(exc.value)
    assert "gemini/empty-content" in exc_str
    assert "groq/empty-content" in exc_str


async def test_error_message_does_not_contain_secrets():
    """Exception messages should not include raw exception strings with potential secrets."""

    class SecretCompletion:
        async def __call__(self, **kwargs):
            model = kwargs["model"]
            if model == "gemini/a":
                raise RuntimeError("boom key=SECRET123 https://example.com?key=SECRET123")
            # Second model also fails with different error
            raise RuntimeError("another boom key=DIFFERENT_SECRET")

    fn = SecretCompletion()
    provider = LiteLLMProvider({"reason": ["gemini/a", "groq/b"]}, completion_fn=fn)
    with pytest.raises(LLMUnavailable) as exc:
        await provider.complete("reason", MSGS)
    exc_str = str(exc.value)
    # Should contain model names and exception type
    assert "gemini/a" in exc_str
    assert "groq/b" in exc_str
    assert "RuntimeError" in exc_str
    # Should NOT contain secrets or raw exception text
    assert "SECRET123" not in exc_str
    assert "DIFFERENT_SECRET" not in exc_str
    assert "boom" not in exc_str
    assert "https://" not in exc_str
