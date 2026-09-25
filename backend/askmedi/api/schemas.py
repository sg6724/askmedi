"""Request body pieces shared by the routers."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, StringConstraints

LanguageField = Literal["en", "hi", "mr"]

TestName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
ShortText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=40)]
RangeText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)]


class LabValueIn(BaseModel):
    model_config = ConfigDict(extra="ignore")

    test_name: TestName
    value: float | None = None
    unit: ShortText | None = None
    ref_low: float | None = None
    ref_high: float | None = None
    ref_text: RangeText | None = None
    status: str | None = None  # ignored: always recomputed in code
