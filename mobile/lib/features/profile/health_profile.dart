enum Sex {
  female('female'),
  male('male'),
  other('other'),
  preferNot('prefer_not');

  const Sex(this.wire);
  final String wire;
}

class HealthProfile {
  const HealthProfile({
    required this.birthYear,
    this.displayName,
    this.sex,
    this.pregnant,
    this.conditions = const [],
    this.medicines = const [],
    this.allergies = const [],
  });

  final String? displayName;
  final int birthYear;
  final Sex? sex;
  final bool? pregnant;
  final List<String> conditions;
  final List<String> medicines;
  final List<String> allergies;
}
