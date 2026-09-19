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

  test('otp validation', () {
    expect(isValidOtp('123456'), isTrue);
    expect(isValidOtp(' 123456 '), isTrue);
    expect(isValidOtp('12345'), isFalse);
    expect(isValidOtp('12a456'), isFalse);
  });
}
