import 'package:askmedi/core/routing/app_status.dart';
import 'package:askmedi/core/routing/routes.dart';
import 'package:flutter_test/flutter_test.dart';

AppStatus status({
  bool lang = true,
  bool signedIn = true,
  bool loaded = true,
  bool consents = true,
  bool profile = true,
}) =>
    AppStatus(
      languageChosen: lang,
      signedIn: signedIn,
      onboardingLoaded: loaded,
      consentsGiven: consents,
      profileComplete: profile,
    );

void main() {
  test('no language -> language screen', () {
    expect(redirectFor(status(lang: false), Routes.splash), Routes.language);
    expect(redirectFor(status(lang: false), Routes.language), isNull);
  });

  test('signed out -> sign in, but OTP sub-route is allowed', () {
    expect(redirectFor(status(signedIn: false), Routes.home), Routes.signIn);
    expect(redirectFor(status(signedIn: false), Routes.signIn), isNull);
    expect(redirectFor(status(signedIn: false), Routes.otp), isNull);
  });

  test('signed in but onboarding not loaded -> splash', () {
    expect(redirectFor(status(loaded: false), Routes.home), Routes.splash);
    expect(redirectFor(status(loaded: false), Routes.splash), isNull);
  });

  test('missing consents -> consent before profile', () {
    expect(redirectFor(status(consents: false, profile: false), Routes.home),
        Routes.consent);
  });

  test('missing profile -> profile setup', () {
    expect(redirectFor(status(profile: false), Routes.consent),
        Routes.profileSetup);
  });

  test('fully onboarded: pre-app routes bounce to home, app routes stay', () {
    expect(redirectFor(status(), Routes.signIn), Routes.home);
    expect(redirectFor(status(), Routes.splash), Routes.home);
    expect(redirectFor(status(), Routes.history), isNull);
    expect(redirectFor(status(), Routes.home), isNull);
  });
}
