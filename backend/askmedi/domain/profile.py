from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True)
class Profile:
    """Minimised health profile. Never contains location or contact details."""

    birth_year: int | None = None
    sex: str | None = None
    pregnant: bool | None = None
    conditions: list[str] = field(default_factory=list)
    medicines: list[str] = field(default_factory=list)  # salt names
    allergies: list[str] = field(default_factory=list)

    def age_band(self, current_year: int) -> str | None:
        if not self.birth_year:
            return None
        age = current_year - self.birth_year
        if age < 18:
            return "under 18"
        if age >= 65:
            return "65+"
        low = (age // 10) * 10
        return f"{low}-{low + 9}"


class ProfileRepository(Protocol):
    async def get_profile(self, user_id: str) -> Profile: ...
