import 'package:askmedi/features/auth/email_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email validation', () {
    expect(isValidEmail('priya@example.com'), isTrue);
    expect(isValidEmail('  priya@example.co.in '), isTrue);
    expect(isValidEmail('priya@'), isFalse);
    expect(isValidEmail('priya.example.com'), isFalse);
    expect(isValidEmail(''), isFalse);
  });

  test('password validation', () {
    expect(isValidPassword('12345678'), isTrue);
    expect(isValidPassword('1234567'), isFalse);
    expect(isValidPassword(''), isFalse);
  });
}
