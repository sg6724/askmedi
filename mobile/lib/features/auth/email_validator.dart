final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _otp = RegExp(r'^\d{6}$');

bool isValidEmail(String input) => _email.hasMatch(input.trim());

bool isValidOtp(String input) => _otp.hasMatch(input.trim());
