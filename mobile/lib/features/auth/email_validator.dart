final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

const minPasswordLength = 8;

bool isValidEmail(String input) => _email.hasMatch(input.trim());

bool isValidPassword(String input) => input.length >= minPasswordLength;
