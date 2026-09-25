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

  test('signed out -> sign in', () {
    expect(redirectFor(status(signedIn: false), Routes.home), Routes.signIn);
    expect(redirectFor(status(signedIn: false), Routes.signIn), isNull);
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

  test('OAuth deep link /login-callback: onboarded user is sent to home', () {
    expect(redirectFor(status(), Routes.loginCallback), Routes.home);
    // The redirect target must itself be stable (no redirect loop).
    expect(redirectFor(status(), Routes.home), isNull);
  });

  test(
      'OAuth deep link /login-callback: signed in, onboarding not loaded -> '
      'splash, which is stable', () {
    final s = status(loaded: false);
    final target = redirectFor(s, Routes.loginCallback);
    expect(target, Routes.splash);
    expect(redirectFor(s, target!), isNull);
  });

  test('OAuth deep link /login-callback never loops for any status', () {
    for (final lang in [true, false]) {
      for (final signedIn in [true, false]) {
        for (final loaded in [true, false]) {
          for (final consents in [true, false]) {
            for (final profile in [true, false]) {
              final s = status(
                  lang: lang,
                  signedIn: signedIn,
                  loaded: loaded,
                  consents: consents,
                  profile: profile);
              final first = redirectFor(s, Routes.loginCallback);
              if (first != null) expect(redirectFor(s, first), isNull);
            }
          }
        }
      }
    }
  });
}
