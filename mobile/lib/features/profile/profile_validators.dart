enum BirthYearError { invalid, under18 }

/// The consent checkbox is the authoritative 18+ confirmation; this is a sanity check.
BirthYearError? validateBirthYear(String input, DateTime now) {
  final year = int.tryParse(input.trim());
  if (input.trim().length != 4 ||
      year == null ||
      year < 1900 ||
      year > now.year) {
    return BirthYearError.invalid;
  }
  if (now.year - year < 18) return BirthYearError.under18;
  return null;
}
