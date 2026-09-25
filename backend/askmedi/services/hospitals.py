"""Nearby hospitals from OpenStreetMap. Coordinates never reach an LLM; logs use 2 dp."""

from typing import Any

from askmedi.domain.audit import AuditEvent, AuditLogger
from askmedi.domain.common import NotFound, ServiceError
from askmedi.domain.geo import (
    DirectoryUnavailable,
    Geocoder,
    GeoPoint,
    PlacesDirectory,
    rank_places,
    round_coord,
)
from askmedi.services.support import safe_audit


class DirectoryError(ServiceError):
    status_code = 502
    code = "directory_unavailable"


class HospitalService:
    def __init__(self, *, geocoder: Geocoder, places: PlacesDirectory, audit: AuditLogger) -> None:
        self._geocoder = geocoder
        self._places = places
        self._audit = audit

    async def search(
        self,
        user_id: str,
        *,
        lat: float | None = None,
        lng: float | None = None,
        pincode: str | None = None,
        q: str | None = None,
        radius_km: float = 5.0,
        specialty: str | None = None,
    ) -> dict[str, Any]:
        try:
            origin = await self._resolve(lat=lat, lng=lng, pincode=pincode, q=q)
            places = await self._places.nearby_health_places(
                origin.lat, origin.lng, int(radius_km * 1000)
            )
        except DirectoryUnavailable as exc:
            raise DirectoryError() from exc
        hospitals = rank_places(
            origin.lat, origin.lng, places, radius_km=radius_km, specialty=specialty
        )
        await safe_audit(
            self._audit,
            AuditEvent(
                user_id=user_id,
                type="hospital_search",
                payload={
                    "lat": round_coord(origin.lat),
                    "lng": round_coord(origin.lng),
                    "by": "coords" if lat is not None else ("pincode" if pincode else "text"),
                    "radius_km": radius_km,
                    "results": len(hospitals),
                },
            ),
        )
        return {
            "location": {"lat": origin.lat, "lng": origin.lng, "label": origin.label},
            "hospitals": hospitals,
        }

    async def _resolve(
        self, *, lat: float | None, lng: float | None, pincode: str | None, q: str | None
    ) -> GeoPoint:
        if lat is not None and lng is not None:
            label = None
            try:
                label = await self._geocoder.reverse(lat, lng)
            except DirectoryUnavailable:
                pass  # the search itself can still work without a label
            return GeoPoint(lat=lat, lng=lng, label=label or "Current location")
        point = await self._geocoder.search(pincode=pincode, q=q)
        if point is None:
            raise NotFound("location_not_found")
        return point
