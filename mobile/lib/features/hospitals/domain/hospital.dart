class Hospital {
  const Hospital({
    required this.name,
    required this.lat,
    required this.lng,
    this.distanceKm,
    this.address,
    this.phone,
    this.emergency,
    this.mapsUrl,
  });

  factory Hospital.fromJson(Map<String, dynamic> j) => Hospital(
    name: (j['name'] as String?) ?? '',
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lng: (j['lng'] as num?)?.toDouble() ?? 0,
    distanceKm: (j['distance_km'] as num?)?.toDouble(),
    address: j['address'] as String?,
    phone: j['phone'] as String?,
    emergency: j['emergency'] as bool?,
    mapsUrl: j['maps_url'] as String?,
  );

  final String name;
  final double lat;
  final double lng;
  final double? distanceKm;
  final String? address;
  final String? phone;
  final bool? emergency;
  final String? mapsUrl;

  String get directionsUrl =>
      mapsUrl ?? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
}

class HospitalSearchResult {
  const HospitalSearchResult({required this.label, required this.hospitals});

  factory HospitalSearchResult.fromJson(Map<String, dynamic> j) =>
      HospitalSearchResult(
        label: ((j['location'] as Map?)?['label'] as String?) ?? '',
        hospitals: [
          for (final h in (j['hospitals'] as List?) ?? const [])
            Hospital.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
      );

  final String label;
  final List<Hospital> hospitals;
}

/// Where to search: coordinates, a 6-digit PIN code, or free area text.
sealed class HospitalQuery {
  const HospitalQuery();

  /// A 6-digit number is a PIN code; anything else is an area name.
  factory HospitalQuery.fromText(String text) {
    final t = text.trim();
    return RegExp(r'^[1-9][0-9]{5}$').hasMatch(t)
        ? PincodeQuery(t)
        : AreaQuery(t);
  }

  Map<String, dynamic> toParams();
}

class CoordsQuery extends HospitalQuery {
  const CoordsQuery(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  Map<String, dynamic> toParams() => {'lat': lat, 'lng': lng};
}

class PincodeQuery extends HospitalQuery {
  const PincodeQuery(this.pincode);
  final String pincode;

  @override
  Map<String, dynamic> toParams() => {'pincode': pincode};
}

class AreaQuery extends HospitalQuery {
  const AreaQuery(this.text);
  final String text;

  @override
  Map<String, dynamic> toParams() => {'q': text};
}
