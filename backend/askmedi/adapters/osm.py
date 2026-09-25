"""OpenStreetMap: Nominatim geocoding and Overpass places. No key; a real User-Agent is required."""

import asyncio
import logging
import math
from collections.abc import Sequence
from typing import Any

import httpx

from askmedi.domain.geo import DirectoryUnavailable, GeoPoint, Place

logger = logging.getLogger(__name__)

NOMINATIM_URL = "https://nominatim.openstreetmap.org"
DEFAULT_OVERPASS_URLS = (
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
)
HEALTHCARE_KINDS = "hospital|clinic|doctor|centre"


def overpass_query(lat: float, lng: float, radius_m: int) -> str:
    around = f"(around:{radius_m},{lat:.6f},{lng:.6f})"
    return (
        "[out:json][timeout:20];("
        f'nwr["amenity"~"^(hospital|clinic)$"]{around};'
        f'nwr["healthcare"~"^({HEALTHCARE_KINDS})$"]{around};'
        ");out center tags 300;"
    )


def _address(tags: dict[str, str]) -> str | None:
    if full := tags.get("addr:full"):
        return full
    street = " ".join(p for p in (tags.get("addr:housenumber"), tags.get("addr:street")) if p)
    parts = [street, tags.get("addr:suburb"), tags.get("addr:city"), tags.get("addr:postcode")]
    text = ", ".join(p for p in parts if p)
    return text or None


def parse_overpass(body: dict[str, Any]) -> list[Place]:
    places: list[Place] = []
    for el in body.get("elements") or []:
        tags = el.get("tags") or {}
        name = tags.get("name:en") or tags.get("name")
        if not name:
            continue
        lat = el.get("lat", (el.get("center") or {}).get("lat"))
        lng = el.get("lon", (el.get("center") or {}).get("lon"))
        if lat is None or lng is None:
            continue
        emergency_tag = tags.get("emergency")
        emergency = True if emergency_tag == "yes" else False if emergency_tag == "no" else None
        places.append(
            Place(
                name=name,
                lat=float(lat),
                lng=float(lng),
                address=_address(tags),
                phone=tags.get("phone") or tags.get("contact:phone"),
                emergency=emergency,
                speciality=tags.get("healthcare:speciality"),
            )
        )
    return places


def parse_nominatim_places(results: list[dict[str, Any]]) -> list[Place]:
    places: list[Place] = []
    for r in results:
        name = r.get("name")
        if not name or r.get("lat") is None or r.get("lon") is None:
            continue
        extra = r.get("extratags") or {}
        addr = r.get("address") or {}
        street = " ".join(p for p in (addr.get("house_number"), addr.get("road")) if p)
        parts = [
            street,
            addr.get("suburb"),
            addr.get("city") or addr.get("town"),
            addr.get("postcode"),
        ]
        emergency_tag = extra.get("emergency")
        places.append(
            Place(
                name=name,
                lat=float(r["lat"]),
                lng=float(r["lon"]),
                address=", ".join(p for p in parts if p) or None,
                phone=extra.get("phone") or extra.get("contact:phone"),
                emergency=True
                if emergency_tag == "yes"
                else False
                if emergency_tag == "no"
                else None,
                speciality=extra.get("healthcare:speciality"),
            )
        )
    return places


class OsmDirectory:
    """Implements the Geocoder and PlacesDirectory ports."""

    def __init__(
        self,
        *,
        user_agent: str,
        overpass_urls: Sequence[str] = DEFAULT_OVERPASS_URLS,
        timeout_s: float = 12.0,
        nominatim_pause_s: float = 1.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._headers = {"User-Agent": user_agent, "Accept-Language": "en"}
        self._overpass_urls = list(overpass_urls)
        self._timeout_s = timeout_s
        self._pause_s = nominatim_pause_s
        self._transport = transport

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            timeout=self._timeout_s, headers=self._headers, transport=self._transport
        )

    async def search(self, *, pincode: str | None = None, q: str | None = None) -> GeoPoint | None:
        params: dict[str, Any] = {
            "format": "jsonv2",
            "limit": 1,
            "countrycodes": "in",
            "addressdetails": 1,
        }
        if pincode:
            params["postalcode"] = pincode
        elif q:
            params["q"] = q
        else:
            return None
        try:
            async with self._client() as client:
                resp = await client.get(f"{NOMINATIM_URL}/search", params=params)
                resp.raise_for_status()
                results = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise DirectoryUnavailable(f"nominatim: {type(exc).__name__}") from exc
        if not results:
            return None
        top = results[0]
        label = str(top.get("display_name") or pincode or q)
        if pincode:
            # "Pune 411001" style label; display_name is long and repeats the country.
            addr = top.get("address") or {}
            place = (
                addr.get("city")
                or addr.get("town")
                or addr.get("state_district")
                or addr.get("county")
                or label.split(",")[0]
            )
            label = f"{place} {pincode}".strip()
        else:
            label = ", ".join(p.strip() for p in label.split(",")[:2])
        return GeoPoint(lat=float(top["lat"]), lng=float(top["lon"]), label=label[:200])

    async def reverse(self, lat: float, lng: float) -> str | None:
        params = {"format": "jsonv2", "lat": f"{lat:.5f}", "lon": f"{lng:.5f}", "zoom": 14}
        try:
            async with self._client() as client:
                resp = await client.get(f"{NOMINATIM_URL}/reverse", params=params)
                resp.raise_for_status()
                body = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise DirectoryUnavailable(f"nominatim: {type(exc).__name__}") from exc
        addr = body.get("address") or {}
        area = addr.get("suburb") or addr.get("neighbourhood") or addr.get("village")
        city = addr.get("city") or addr.get("town") or addr.get("county")
        label = ", ".join(p for p in (area, city) if p)
        return label or body.get("display_name")

    async def nearby_health_places(self, lat: float, lng: float, radius_m: int) -> list[Place]:
        query = overpass_query(lat, lng, radius_m)
        errors: list[str] = []
        async with self._client() as client:
            for url in self._overpass_urls:
                try:
                    resp = await client.post(url, data={"data": query})
                    resp.raise_for_status()
                    return parse_overpass(resp.json())
                except (httpx.HTTPError, ValueError) as exc:
                    errors.append(f"{url}: {type(exc).__name__}")
                    logger.warning("overpass failed at %s: %s", url, type(exc).__name__)
            # Overpass is often overloaded; Nominatim's POI search is a smaller but steadier source.
            try:
                return await self._nominatim_places(client, lat, lng, radius_m)
            except (httpx.HTTPError, ValueError) as exc:
                errors.append(f"nominatim: {type(exc).__name__}")
        raise DirectoryUnavailable("; ".join(errors))

    async def _nominatim_places(
        self, client: httpx.AsyncClient, lat: float, lng: float, radius_m: int
    ) -> list[Place]:
        dlat = radius_m / 111_000
        dlng = radius_m / (111_000 * max(math.cos(math.radians(lat)), 0.01))
        viewbox = f"{lng - dlng:.5f},{lat + dlat:.5f},{lng + dlng:.5f},{lat - dlat:.5f}"
        places: list[Place] = []
        for i, amenity in enumerate(("hospital", "clinic")):
            if i:
                await asyncio.sleep(
                    self._pause_s
                )  # Nominatim usage policy: at most 1 request per second
            resp = await client.get(
                f"{NOMINATIM_URL}/search",
                params={
                    "amenity": amenity,
                    "viewbox": viewbox,
                    "bounded": 1,
                    "limit": 40,
                    "format": "jsonv2",
                    "extratags": 1,
                    "addressdetails": 1,
                },
            )
            resp.raise_for_status()
            places.extend(parse_nominatim_places(resp.json()))
        return places
