from types import SimpleNamespace

import pytest

from askmedi.adapters.litellm_vision import LiteLLMVisionReader
from askmedi.adapters.reader_chain import DocumentReaderChain
from askmedi.domain.search import UnreadableDocument, VisionUnavailable


class _Reader:
    def __init__(self, result=None, error: Exception | None = None) -> None:
        self.result, self.error, self.calls = result, error, 0

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict:
        self.calls += 1
        if self.error:
            raise self.error
        return self.result


def _completion(text: str | None = None, error: Exception | None = None):
    calls: list[dict] = []

    async def fake(**kwargs):
        calls.append(kwargs)
        if error:
            raise error
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=text))])

    return fake, calls


async def test_chain_uses_first_reader_that_works():
    first, second = _Reader(error=VisionUnavailable("quota")), _Reader(result={"ok": 1})
    assert await DocumentReaderChain([first, second]).read_json("p", b"x", "image/png") == {"ok": 1}
    assert (first.calls, second.calls) == (1, 1)


async def test_chain_does_not_retry_unreadable_documents():
    first, second = _Reader(error=UnreadableDocument("junk")), _Reader(result={"ok": 1})
    with pytest.raises(UnreadableDocument):
        await DocumentReaderChain([first, second]).read_json("p", b"x", "image/png")
    assert second.calls == 0


async def test_chain_raises_when_every_reader_is_unavailable():
    readers = [_Reader(error=VisionUnavailable("a")), _Reader(error=VisionUnavailable("b"))]
    with pytest.raises(VisionUnavailable):
        await DocumentReaderChain(readers).read_json("p", b"x", "image/png")


async def test_litellm_reader_sends_image_as_data_url_and_parses_json():
    fake, calls = _completion('{"brand": "Crocin"}')
    reader = LiteLLMVisionReader(["groq/qwen/qwen3.8-27b"], completion=fake)
    assert await reader.read_json("read it", b"\x89PNG", "image/png") == {"brand": "Crocin"}
    content = calls[0]["messages"][0]["content"]
    assert content[0] == {"type": "text", "text": "read it"}
    assert content[1]["image_url"]["url"].startswith("data:image/png;base64,")
    assert calls[0]["model"] == "groq/qwen/qwen3.8-27b"


async def test_litellm_reader_skips_pdfs():
    fake, calls = _completion('{"a": 1}')
    with pytest.raises(VisionUnavailable):
        await LiteLLMVisionReader(["groq/x"], completion=fake).read_json(
            "p", b"%PDF", "application/pdf"
        )
    assert calls == []


async def test_litellm_reader_falls_through_models_then_gives_up():
    fake, calls = _completion(error=RuntimeError("down"))
    with pytest.raises(VisionUnavailable):
        await LiteLLMVisionReader(["groq/a", "groq/b"], completion=fake).read_json(
            "p", b"i", "image/jpeg"
        )
    assert [c["model"] for c in calls] == ["groq/a", "groq/b"]


async def test_litellm_reader_non_json_answer_is_unreadable():
    fake, _ = _completion("I cannot read this")
    with pytest.raises(UnreadableDocument):
        await LiteLLMVisionReader(["groq/a"], completion=fake).read_json("p", b"i", "image/jpeg")
