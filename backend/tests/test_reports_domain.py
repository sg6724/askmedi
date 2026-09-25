import pytest

from askmedi.domain.reports import compute_status, normalise_value, parse_ref_text


@pytest.mark.parametrize(
    ("value", "low", "high", "status"),
    [
        (11.2, 12, 15.5, "low"),
        (13.0, 12, 15.5, "normal"),
        (12.0, 12, 15.5, "normal"),  # boundaries are inside the range
        (15.5, 12, 15.5, "normal"),
        (16.1, 12, 15.5, "high"),
        (250, None, 200, "high"),
        (150, None, 200, "normal"),
        (35, 40, None, "low"),
        (5.0, None, None, "unknown"),
        (None, 12, 15.5, "unreadable"),
    ],
)
def test_compute_status(value, low, high, status):
    assert compute_status(value, low, high) == status


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("12.0-15.5", (12.0, 15.5)),
        ("12.0 - 15.5 g/dL", (12.0, 15.5)),
        ("4,000 to 11,000", (4000.0, 11000.0)),
        ("12,5-15,5", (12.5, 15.5)),
        ("< 200", (None, 200.0)),
        ("Upto 40", (None, 40.0)),
        (">= 40", (40.0, None)),
        ("15.5-12.0", (12.0, 15.5)),
        ("Negative", (None, None)),
        (None, (None, None)),
    ],
)
def test_parse_ref_text(text, expected):
    assert parse_ref_text(text) == expected


def test_normalise_value_uses_printed_range_when_bounds_missing():
    v = normalise_value(
        {"test_name": " Haemoglobin ", "value": "11.2", "unit": "g/dL", "ref_text": "12.0-15.5"}
    )
    assert v is not None
    assert (v.test_name, v.value, v.ref_low, v.ref_high, v.status) == (
        "Haemoglobin",
        11.2,
        12.0,
        15.5,
        "low",
    )


def test_normalise_value_ignores_given_status_and_marks_unreadable():
    v = normalise_value(
        {"test_name": "TSH", "value": "N/A", "ref_low": 0.4, "ref_high": 4.0, "status": "normal"}
    )
    assert v.status == "unreadable"


def test_normalise_value_without_range_is_unknown():
    v = normalise_value({"test_name": "Vitamin D", "value": 25})
    assert v.status == "unknown"


def test_normalise_value_requires_a_name():
    assert normalise_value({"test_name": "  ", "value": 1}) is None
