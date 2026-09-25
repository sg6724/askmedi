import time
from collections import OrderedDict
from collections.abc import Callable, Sequence

from askmedi.domain.search import GroundedText, SearchUnavailable, WebSearch


class WebSearchChain:
    """Tries each search in order; the first result with sources wins.

    Sourced results are cached in memory for `cache_ttl_s`: a web search reads whole pages
    (~5k tokens) against a free-tier budget of 8k tokens per minute, so an identical
    question within the TTL (same warm instance) is answered instantly and for free.
    """

    def __init__(
        self,
        searches: Sequence[WebSearch],
        *,
        cache_ttl_s: float = 6 * 3600,
        cache_size: int = 256,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._searches = list(searches)
        self._ttl = cache_ttl_s
        self._size = cache_size
        self._clock = clock
        self._cache: OrderedDict[str, tuple[float, GroundedText]] = OrderedDict()

    async def research(self, question: str, keywords: Sequence[str] = ()) -> GroundedText:
        key = " ".join(question.lower().split())
        hit = self._cache.get(key)
        if hit and self._clock() - hit[0] < self._ttl:
            self._cache.move_to_end(key)
            return hit[1]

        unsourced: GroundedText | None = None
        errors: list[str] = []
        for search in self._searches:
            try:
                result = await search.research(question, keywords)
            except SearchUnavailable as exc:
                errors.append(str(exc))
                continue
            if result.sources:
                self._remember(key, result)
                return result
            unsourced = unsourced or result
        if unsourced is not None:
            return unsourced
        raise SearchUnavailable("; ".join(errors))

    def _remember(self, key: str, result: GroundedText) -> None:
        self._cache[key] = (self._clock(), result)
        self._cache.move_to_end(key)
        while len(self._cache) > self._size:
            self._cache.popitem(last=False)
