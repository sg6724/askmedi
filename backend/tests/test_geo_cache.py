from askmedi.adapters.geo_cache import CachedGeocoder, CachedPlaces
from askmedi.domain.geo import GeoPoint


class CountingGeocoder:
    def __init__(self):
        self.calls = 0

    async def search(self, *, pincode=None, q=None):
        self.calls += 1
        return GeoPoint(lat=18.52, lng=73.85, label=pincode or q)

    async def reverse(self, lat, lng):
        self.calls += 1
        return "Pune"


class CountingPlaces:
    def __init__(self):
        self.calls = 0

    async def nearby_health_places(self, lat, lng, radius_m):
        self.calls += 1
        return [f"place-{self.calls}"]


async def test_geocoder_results_are_cached_per_query():
    inner = CountingGeocoder()
    geo = CachedGeocoder(inner, ttl_s=60)
    a = await geo.search(pincode="411001")
    b = await geo.search(pincode="411001")
    await geo.search(q="Kothrud")
    assert a == b and inner.calls == 2
    assert await geo.reverse(18.5204, 73.8567) == await geo.reverse(18.5201, 73.8569)
    assert inner.calls == 3  # reverse cached at ~100 m precision


async def test_places_are_cached_per_rounded_point_and_radius():
    inner = CountingPlaces()
    clock = [0.0]
    places = CachedPlaces(inner, ttl_s=60, clock=lambda: clock[0])
    first = await places.nearby_health_places(18.52041, 73.85671, 5000)
    again = await places.nearby_health_places(18.52039, 73.85669, 5000)  # same ~100 m cell
    wider = await places.nearby_health_places(18.52041, 73.85671, 10000)
    assert first == again and wider != first and inner.calls == 2

    clock[0] = 61
    await places.nearby_health_places(18.52041, 73.85671, 5000)
    assert inner.calls == 3


async def test_empty_place_lists_are_not_cached():
    class Empty(CountingPlaces):
        async def nearby_health_places(self, lat, lng, radius_m):
            self.calls += 1
            return []

    inner = Empty()
    places = CachedPlaces(inner, ttl_s=60)
    await places.nearby_health_places(1, 2, 5000)
    await places.nearby_health_places(1, 2, 5000)
    assert inner.calls == 2
