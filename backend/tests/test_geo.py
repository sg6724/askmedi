from askmedi.domain.geo import Place, haversine_km, maps_url, rank_places, round_coord

ORIGIN = (18.5204, 73.8567)  # Pune


def test_haversine_known_distance():
    # Pune -> Mumbai is roughly 120 km in a straight line.
    assert 115 < haversine_km(*ORIGIN, 19.0760, 72.8777) < 125
    assert haversine_km(*ORIGIN, *ORIGIN) == 0


def test_rank_places_sorts_by_distance_dedupes_and_filters_radius():
    places = [
        Place("Far Hospital", 18.60, 73.90),
        Place("Near Clinic", 18.521, 73.857),
        Place("Mid Hospital", 18.53, 73.86),
        Place("Near Clinic", 18.5210, 73.8570),  # duplicate
        Place("Out of range", 19.2, 72.9),
    ]
    rows = rank_places(*ORIGIN, places, radius_km=15)
    assert [r["name"] for r in rows] == ["Near Clinic", "Mid Hospital", "Far Hospital"]
    assert rows[0]["distance_km"] <= rows[1]["distance_km"] <= rows[2]["distance_km"]
    assert rows[0]["maps_url"] == maps_url(18.521, 73.857)
    assert rows[0]["maps_url"].startswith("https://www.google.com/maps/search/?api=1&query=")


def test_rank_places_caps_at_30():
    places = [Place(f"P{i}", 18.52 + i * 0.0001, 73.8567) for i in range(50)]
    assert len(rank_places(*ORIGIN, places, radius_km=5)) == 30


def test_specialty_filter_falls_back_to_all_when_nothing_matches():
    places = [
        Place("City Eye Hospital", 18.53, 73.86),
        Place("General Hospital", 18.521, 73.857, speciality="cardiology"),
    ]
    assert [r["name"] for r in rank_places(*ORIGIN, places, radius_km=5, specialty="eye")] == [
        "City Eye Hospital"
    ]
    assert [r["name"] for r in rank_places(*ORIGIN, places, radius_km=5, specialty="cardio")] == [
        "General Hospital"
    ]
    assert len(rank_places(*ORIGIN, places, radius_km=5, specialty="dental")) == 2


def test_round_coord_is_two_decimals():
    assert round_coord(18.520412) == 18.52
