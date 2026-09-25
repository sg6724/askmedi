from collections.abc import Sequence

from askmedi.domain.search import GroundedText, SearchUnavailable, WebSearch


class WebSearchChain:
    """Tries each search in order; the first result with sources wins."""

    def __init__(self, searches: Sequence[WebSearch]) -> None:
        self._searches = list(searches)

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText:
        unsourced: GroundedText | None = None
        errors: list[str] = []
        for search in self._searches:
            try:
                result = await search.research(question, keywords)
            except SearchUnavailable as exc:
                errors.append(str(exc))
                continue
            if result.sources:
                return result
            unsourced = unsourced or result
        if unsourced is not None:
            return unsourced
        raise SearchUnavailable("; ".join(errors))
