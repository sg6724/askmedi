import httpx
import pytest

from askmedi.adapters.medlineplus import MedlinePlusSearch, parse_results
from askmedi.adapters.search_chain import WebSearchChain
from askmedi.domain.common import Source
from askmedi.domain.search import GroundedText, SearchUnavailable
from tests.fakes import FakeSearch

XML = """<?xml version="1.0" encoding="UTF-8"?>
<nlmSearchResult><list num="1">
  <document rank="0" url="https://medlineplus.gov/fever.html">
    <content name="title">&lt;span class="qt0"&gt;Fever&lt;/span&gt;</content>
    <content name="FullSummary">&lt;p&gt;A &lt;span&gt;fever&lt;/span&gt; is a body temperature
      that is higher than normal.&lt;/p&gt;</content>
  </document>
</list></nlmSearchResult>"""


def test_parse_results_strips_markup():
    assert parse_results(XML) == [
        (
            "Fever",
            "https://medlineplus.gov/fever.html",
            "A fever is a body temperature that is higher than normal.",
        )
    ]


async def test_medlineplus_search_uses_keywords():
    terms = []

    def handler(request):
        terms.append(request.url.params["term"])
        assert request.url.params["db"] == "healthTopics"
        return httpx.Response(200, text=XML)

    out = await MedlinePlusSearch(transport=httpx.MockTransport(handler)).research(
        "long question", ["fever", "headache"]
    )
    assert terms == ["fever", "headache"]
    assert out.sources == [Source("MedlinePlus: Fever", "https://medlineplus.gov/fever.html")]
    assert "higher than normal" in out.text


async def test_medlineplus_needs_keywords():
    with pytest.raises(SearchUnavailable):
        await MedlinePlusSearch().research("q", [])


class Unsourced:
    async def research(self, question, keywords=()):
        return GroundedText(text="no sources", sources=[])


async def test_chain_falls_back_until_a_result_has_sources():
    backup = FakeSearch()
    out = await WebSearchChain([FakeSearch(fail=True), Unsourced(), backup]).research("q", ["k"])
    assert out.sources and backup.keywords == [["k"]]


async def test_chain_returns_unsourced_text_or_raises():
    out = await WebSearchChain([Unsourced(), FakeSearch(fail=True)]).research("q")
    assert out.text == "no sources"
    with pytest.raises(SearchUnavailable):
        await WebSearchChain([FakeSearch(fail=True)]).research("q")
