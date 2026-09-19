import 'package:askmedi/features/profile/profile_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 19);

  test('valid adult year', () {
    expect(validateBirthYear('1995', now), isNull);
    expect(validateBirthYear('2008', now), isNull); // turns 18 this year
  });

  test('under 18 rejected', () {
    expect(validateBirthYear('2009', now), BirthYearError.under18);
  });

  test('malformed or implausible rejected', () {
    expect(validateBirthYear('', now), BirthYearError.invalid);
    expect(validateBirthYear('95', now), BirthYearError.invalid);
    expect(validateBirthYear('abcd', now), BirthYearError.invalid);
    expect(validateBirthYear('1890', now), BirthYearError.invalid);
    expect(validateBirthYear('2030', now), BirthYearError.invalid);
  });
}
