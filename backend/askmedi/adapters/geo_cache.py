"""In-memory caches around the OpenStreetMap geocoder and places directory.

Nominatim asks for at most 1 request/s and Overpass is often slow (5-20 s), while hospitals near a
place barely change within hours. Points are cached at 3 decimal places (~100 m); coordinates stay
in this process only and are never logged.
"""

import time
from collections import OrderedDict
from collections.abc import Callable, Hashable
from typing import Any

from askmedi.domain.geo import Geocoder, GeoPoint, Place, PlacesDirectory


class _TtlCache:
    def __init__(self, ttl_s: float, size: int, clock: Callable[[], float]) -> None:
        self._ttl, self._size, self._clock = ttl_s, size, clock
        self._items: OrderedDict[Hashable, tuple[float, Any]] = OrderedDict()

    def get(self, key: Hashable) -> tuple[bool, Any]:
        hit = self._items.get(key)
        if hit is None or self._clock() - hit[0] >= self._ttl:
            return False, None
        self._items.move_to_end(key)
        return True, hit[1]

    def put(self, key: Hashable, value: Any) -> None:
        self._items[key] = (self._clock(), value)
        self._items.move_to_end(key)
        while len(self._items) > self._size:
            self._items.popitem(last=False)


def _cell(lat: float, lng: float) -> tuple[float, float]:
    return round(lat, 3), round(lng, 3)


class CachedGeocoder:
    """Implements the Geocoder port over another Geocoder."""

    def __init__(
        self,
        inner: Geocoder,
        *,
        ttl_s: float = 24 * 3600,
        size: int = 512,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._inner = inner
        self._cache = _TtlCache(ttl_s, size, clock)

    async def search(self, *, pincode: str | None = None, q: str | None = None) -> GeoPoint | None:
        key = ("search", pincode, " ".join((q or "").lower().split()))
        found, value = self._cache.get(key)
        if found:
            return value
        point = await self._inner.search(pincode=pincode, q=q)
        if point is not None:
            self._cache.put(key, point)
        return point

    async def reverse(self, lat: float, lng: float) -> str | None:
        key = ("reverse", *_cell(lat, lng))
        found, value = self._cache.get(key)
        if found:
            return value
        label = await self._inner.reverse(lat, lng)
        if label is not None:
            self._cache.put(key, label)
        return label


class CachedPlaces:
    """Implements the PlacesDirectory port over another PlacesDirectory."""

    def __init__(
        self,
        inner: PlacesDirectory,
        *,
        ttl_s: float = 6 * 3600,
        size: int = 256,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._inner = inner
        self._cache = _TtlCache(ttl_s, size, clock)

    async def nearby_health_places(self, lat: float, lng: float, radius_m: int) -> list[Place]:
        key = (*_cell(lat, lng), radius_m)
        found, value = self._cache.get(key)
        if found:
            return value
        places = await self._inner.nearby_health_places(lat, lng, radius_m)
        if places:
            self._cache.put(key, places)
        return places
