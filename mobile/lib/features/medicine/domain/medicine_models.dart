import '../../../shared/source.dart';

class Salt {
  const Salt({required this.name, this.strength});

  factory Salt.fromJson(Map<String, dynamic> j) => Salt(
    name: (j['name'] as String?) ?? '',
    strength: j['strength'] as String?,
  );

  final String name;
  final String? strength;

  @override
  String toString() =>
      (strength == null || strength!.isEmpty) ? name : '$name $strength';

  static List<Salt> listFrom(Object? json) => [
    for (final s in (json as List?) ?? const [])
      Salt.fromJson(Map<String, dynamic>.from(s as Map)),
  ];
}

class MedicineCandidate {
  const MedicineCandidate({
    required this.brand,
    required this.salts,
    this.form,
    this.manufacturer,
    this.confidence,
  });

  factory MedicineCandidate.fromJson(Map<String, dynamic> j) =>
      MedicineCandidate(
        brand: (j['brand'] as String?) ?? '',
        salts: Salt.listFrom(j['salts']),
        form: j['form'] as String?,
        manufacturer: j['manufacturer'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
      );

  final String brand;
  final List<Salt> salts;
  final String? form;
  final String? manufacturer;
  final double? confidence;

  String get saltsText => salts.join(', ');

  /// What to look up: the first salt (generic name), else the brand.
  String get lookupName => salts.isNotEmpty ? salts.first.name : brand;
}

class MedicineInfo {
  const MedicineInfo({
    required this.name,
    this.brand,
    this.salts = const [],
    this.uses = const [],
    this.warnings = const [],
    this.pharmacistFlags = const [],
    this.summary = '',
    this.sources = const [],
    this.disclaimer = '',
  });

  factory MedicineInfo.fromJson(Map<String, dynamic> j) => MedicineInfo(
    name: (j['name'] as String?) ?? '',
    brand: j['brand'] as String?,
    salts: Salt.listFrom(j['salts']),
    uses: stringList(j['uses']),
    warnings: stringList(j['warnings']),
    pharmacistFlags: [
      for (final f in (j['pharmacist_flags'] as List?) ?? const [])
        if (f is Map) (f['reason'] as String?) ?? '' else f.toString(),
    ],
    summary: (j['summary'] as String?) ?? '',
    sources: Source.listFrom(j['sources']),
    disclaimer: (j['disclaimer'] as String?) ?? '',
  );

  final String name;
  final String? brand;
  final List<Salt> salts;
  final List<String> uses;
  final List<String> warnings;

  /// Each is a full sentence, e.g. "Check with your pharmacist because …".
  final List<String> pharmacistFlags;
  final String summary;
  final List<Source> sources;
  final String disclaimer;
}
