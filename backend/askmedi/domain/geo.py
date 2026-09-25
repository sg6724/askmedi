"""Hospital search: ports and pure geo logic. Coordinates never go to an LLM."""

import math
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(frozen=True)
class GeoPoint:
    lat: float
    lng: float
    label: str


@dataclass(frozen=True)
class Place:
    name: str
    lat: float
    lng: float
    address: str | None = None
    phone: str | None = None
    emergency: bool | None = None
    speciality: str | None = None


class DirectoryUnavailable(Exception):
    """The geocoder or places directory could not be reached."""


class Geocoder(Protocol):
    async def search(
        self, *, pincode: str | None = None, q: str | None = None
    ) -> GeoPoint | None: ...

    async def reverse(self, lat: float, lng: float) -> str | None: ...


class PlacesDirectory(Protocol):
    async def nearby_health_places(self, lat: float, lng: float, radius_m: int) -> list[Place]: ...


EARTH_RADIUS_KM = 6371.0088


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def maps_url(lat: float, lng: float) -> str:
    return f"https://www.google.com/maps/search/?api=1&query={lat:.6f},{lng:.6f}"


def rank_places(
    origin_lat: float,
    origin_lng: float,
    places: list[Place],
    *,
    radius_km: float,
    specialty: str | None = None,
    limit: int = 30,
) -> list[dict[str, Any]]:
    """Dedupes, optionally filters by specialty, sorts by distance and caps the list."""
    seen: set[tuple[str, float, float]] = set()
    rows: list[dict[str, Any]] = []
    for place in places:
        key = (place.name.lower(), round(place.lat, 3), round(place.lng, 3))
        if key in seen:
            continue
        seen.add(key)
        dist = haversine_km(origin_lat, origin_lng, place.lat, place.lng)
        if dist > radius_km:
            continue
        rows.append({"place": place, "distance": dist})

    if specialty:
        needle = specialty.strip().lower()
        matching = [
            r
            for r in rows
            if needle in (r["place"].speciality or "").lower() or needle in r["place"].name.lower()
        ]
        # OSM rarely tags specialities; when nothing matches, show all nearby places instead
        # of an empty list (a general hospital can still help).
        if matching:
            rows = matching

    rows.sort(key=lambda r: r["distance"])
    return [
        {
            "name": r["place"].name,
            "lat": r["place"].lat,
            "lng": r["place"].lng,
            "distance_km": round(r["distance"], 2),
            "address": r["place"].address,
            "phone": r["place"].phone,
            "emergency": r["place"].emergency,
            "maps_url": maps_url(r["place"].lat, r["place"].lng),
        }
        for r in rows[:limit]
    ]


def round_coord(value: float) -> float:
    """Coordinates are rounded to 2 dp (about 1 km) before they are logged."""
    return round(value, 2)
