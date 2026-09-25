import json

import httpx
import pytest

from askmedi.adapters.groq_search import GroqWebSearch
from askmedi.domain.search import SearchUnavailable


def _response(content: str, results: list[dict]) -> dict:
    return {
        "choices": [
            {
                "message": {
                    "role": "assistant",
                    "content": content,
                    "executed_tools": [
                        {"type": "browser_search", "search_results": {"results": results}},
                        # Pages the model opened are not search results; ignored.
                        {
                            "type": "browser.open",
                            "search_results": {
                                "results": [{"title": "exa", "url": "https://exa.ai/search?q=x"}]
                            },
                        },
                    ],
                }
            }
        ]
    }


async def test_research_returns_clean_text_and_search_sources():
    seen = {}

    def handler(request):
        seen["body"] = json.loads(request.content)
        seen["auth"] = request.headers["authorization"]
        return httpx.Response(
            200,
            json=_response(
                "ZADY 500 contains azithromycin 500 mg【2†L6-L7】. It is an antibiotic【2†L8】.",
                [
                    {"title": "Zady 500 - Practo", "url": "https://www.practo.com/zady"},
                    {"title": "Azithromycin - DailyMed", "url": "https://dailymed.nlm.nih.gov/a"},
                    {"title": "dup", "url": "https://www.practo.com/zady"},
                    {"title": "no url"},
                ],
            ),
        )

    search = GroqWebSearch(
        "key", models=["openai/gpt-oss-120b"], transport=httpx.MockTransport(handler)
    )
    result = await search.research("What is ZADY 500?")

    assert result.text == "ZADY 500 contains azithromycin 500 mg. It is an antibiotic."
    assert [s.url for s in result.sources] == [
        "https://www.practo.com/zady",
        "https://dailymed.nlm.nih.gov/a",
    ]
    assert result.model == "groq/openai/gpt-oss-120b"
    assert seen["auth"] == "Bearer key"
    assert seen["body"]["tools"] == [{"type": "browser_search"}]
    assert seen["body"]["model"] == "openai/gpt-oss-120b"


async def test_litellm_style_model_prefix_is_stripped():
    models = []

    def handler(request):
        models.append(json.loads(request.content)["model"])
        return httpx.Response(200, json=_response("ok", [{"title": "t", "url": "https://a.b"}]))

    await GroqWebSearch(
        "k", models=["groq/openai/gpt-oss-20b"], transport=httpx.MockTransport(handler)
    ).research("q")
    assert models == ["openai/gpt-oss-20b"]


async def test_falls_through_models_then_raises():
    calls = []

    def handler(request):
        calls.append(json.loads(request.content)["model"])
        return httpx.Response(429, json={"error": {"message": "rate limited"}})

    search = GroqWebSearch("k", models=["a", "b"], transport=httpx.MockTransport(handler))
    with pytest.raises(SearchUnavailable):
        await search.research("q")
    assert calls == ["a", "b"]


async def test_empty_answer_counts_as_failure():
    search = GroqWebSearch(
        "k",
        models=["a"],
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json=_response("  ", []))),
    )
    with pytest.raises(SearchUnavailable):
        await search.research("q")
