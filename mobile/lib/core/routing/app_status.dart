import 'routes.dart';

class AppStatus {
  const AppStatus({
    required this.languageChosen,
    required this.introSeen,
    required this.signedIn,
    required this.onboardingLoaded,
    required this.consentsGiven,
    required this.profileComplete,
  });

  final bool languageChosen;

  /// The welcome slides (what AskMedi does) have been shown on this device.
  final bool introSeen;
  final bool signedIn;
  final bool onboardingLoaded;
  final bool consentsGiven;
  final bool profileComplete;
}

/// Returns where the user must go, or null to stay on [location].
String? redirectFor(AppStatus s, String location) {
  final gate = _gateFor(s);
  if (gate == null) {
    return Routes.preApp.contains(location) ? Routes.home : null;
  }
  if (gate == Routes.signIn && location.startsWith(Routes.signIn)) return null;
  return location == gate ? null : gate;
}

String? _gateFor(AppStatus s) {
  if (!s.languageChosen) return Routes.language;
  if (!s.introSeen) return Routes.welcome;
  if (!s.signedIn) return Routes.signIn;
  if (!s.onboardingLoaded) return Routes.splash;
  if (!s.consentsGiven) return Routes.consent;
  if (!s.profileComplete) return Routes.profileSetup;
  return null;
}
