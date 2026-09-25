import 'dart:async';

import 'package:askmedi/app.dart';
import 'package:askmedi/core/l10n/gen/app_localizations.dart';
import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/providers.dart';
import 'package:askmedi/core/routing/router.dart';
import 'package:askmedi/core/routing/routes.dart';
import 'package:askmedi/features/auth/auth_repository.dart';
import 'package:askmedi/features/auth/sign_in_screen.dart';
import 'package:askmedi/features/consent/consent_purpose.dart';
import 'package:askmedi/features/consent/consent_repository.dart';
import 'package:askmedi/features/history/data/history_repository.dart';
import 'package:askmedi/features/history/domain/history_models.dart';
import 'package:askmedi/features/home/home_screen.dart';
import 'package:askmedi/features/profile/data/account_repository.dart';
import 'package:askmedi/features/profile/health_profile.dart';
import 'package:askmedi/features/profile/onboarding_repository.dart';
import 'package:askmedi/features/profile/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- Fakes: no network, no Supabase ----------------------------------------

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this._signedIn = false});

  bool _signedIn;
  final _changes = StreamController<bool>.broadcast();
  String? signedInAs;

  void setSignedIn(bool value) {
    _signedIn = value;
    _changes.add(value);
  }

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> watchSignedIn() => _changes.stream;

  @override
  Future<void> signOut() async => setSignedIn(false);

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signedInAs = email;
    setSignedIn(true);
  }

  @override
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    signedInAs = email;
    setSignedIn(true);
    return true;
  }

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<String?> accessToken() async => null;
}

class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository(this.status, {this.error});

  OnboardingStatus status;
  Object? error;
  int fetches = 0;

  @override
  Future<OnboardingStatus> fetch() async {
    fetches++;
    if (error != null) throw error!;
    return status;
  }
}

class FakeConsentRepository implements ConsentRepository {
  FakeConsentRepository(this._onboarding);
  final FakeOnboardingRepository _onboarding;
  Map<ConsentPurpose, bool>? saved;

  @override
  Future<void> save(Map<ConsentPurpose, bool> choices) async {
    saved = choices;
    _onboarding.status = OnboardingStatus(
      consentsGiven: true,
      profileComplete: _onboarding.status.profileComplete,
    );
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this._onboarding);
  final FakeOnboardingRepository _onboarding;
  HealthProfile? saved;
  String? savedLanguage;

  @override
  Future<void> saveOnboardingProfile(
    HealthProfile profile, {
    required String language,
  }) async {
    saved = profile;
    savedLanguage = language;
    _onboarding.status = const OnboardingStatus(
      consentsGiven: true,
      profileComplete: true,
    );
  }

  @override
  Future<HealthProfile?> loadProfile() async => saved;

  @override
  Future<void> updateProfile(HealthProfile profile, {required String language}) async {
    saved = profile;
    savedLanguage = language;
  }
}

class FakeHistoryRepository implements HistoryRepository {
  @override
  Future<HistoryData> load() async => const HistoryData();
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this._auth);
  final FakeAuthRepository _auth;
  int deletes = 0;

  @override
  Future<void> deleteAccount() async {
    deletes++;
    // The real RPC removes the user; the session is then useless.
    expect(_auth.isSignedIn, isTrue);
  }
}

// -- Harness ---------------------------------------------------------------

const _none = OnboardingStatus(consentsGiven: false, profileComplete: false);
const _consentsOnly = OnboardingStatus(
  consentsGiven: true,
  profileComplete: false,
);
const _done = OnboardingStatus(consentsGiven: true, profileComplete: true);

class World {
  World({
    bool signedIn = false,
    OnboardingStatus status = _none,
    Object? fetchError,
    this.displayName,
    this.meError,
  }) : auth = FakeAuthRepository(signedIn: signedIn),
       onboarding = FakeOnboardingRepository(status, error: fetchError) {
    consent = FakeConsentRepository(onboarding);
    profile = FakeProfileRepository(onboarding);
    account = FakeAccountRepository(auth);
  }

  final FakeAuthRepository auth;
  final FakeOnboardingRepository onboarding;
  late final FakeConsentRepository consent;
  late final FakeProfileRepository profile;
  late final FakeAccountRepository account;

  /// Read by the `displayNameProvider` override each time it is (re)computed.
  String? displayName;

  /// When set, the `meProvider` override throws it instead of answering.
  Object? meError;

  /// How many times the `meProvider` override has been computed.
  int meCalls = 0;
}

/// Tall viewport: the ListView-based screens build lazily, so every widget
/// (including the bottom buttons) must fit on screen to be found.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpApp(
  WidgetTester tester,
  World world, {
  Map<String, Object> prefs = const {'app_locale': 'en'},
  bool settle = true,
}) async {
  _tallViewport(tester);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        authRepositoryProvider.overrideWithValue(world.auth),
        onboardingRepositoryProvider.overrideWithValue(world.onboarding),
        consentRepositoryProvider.overrideWithValue(world.consent),
        profileRepositoryProvider.overrideWithValue(world.profile),
        historyRepositoryProvider.overrideWithValue(FakeHistoryRepository()),
        accountRepositoryProvider.overrideWithValue(world.account),
        // Overrides keep the real providers' autoDispose/retry behaviour, so
        // these exercise the production provider configuration.
        meProvider.overrideWith((ref) async {
          world.meCalls++;
          if (world.meError != null) throw world.meError!;
          return const MeResponse(userId: 'u-1');
        }),
        displayNameProvider.overrideWith((ref) async => world.displayName),
      ],
      child: const AskMediApp(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder inNavBar(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// The app's real router, read out of the widget tree's provider container.
GoRouter routerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AskMediApp)))
        .read(routerProvider);

/// Full location of the top page, including pushed routes (the router's
/// routeInformationProvider only reports the last go()).
String locationOf(WidgetTester tester) =>
    routerOf(tester).routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  testWidgets('no saved language -> language screen; English + Continue -> '
      'sign in', (tester) async {
    await pumpApp(tester, World(), prefs: const {});

    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to AskMedi'), findsOneWidget);
    expect(find.text('Choose your language'), findsNothing);
  });

  testWidgets('email + password sign-in moves on to consent', (tester) async {
    final world = World(status: _none);
    await pumpApp(tester, world);
    expect(find.text('Sign in to AskMedi'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email address'),
      'a@test.dev',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'correct-horse',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(world.auth.signedInAs, 'a@test.dev');
    expect(find.text('Before we begin'), findsOneWidget);
  });

  testWidgets('signed in, no consents -> consent screen', (tester) async {
    await pumpApp(tester, World(signedIn: true, status: _none));

    expect(find.text('Before we begin'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Agree and continue'),
      findsOneWidget,
    );
  });

  testWidgets('signed in, consents ok, no profile -> profile setup', (
    tester,
  ) async {
    await pumpApp(tester, World(signedIn: true, status: _consentsOnly));

    expect(find.text('Your health profile'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Birth year'), findsOneWidget);
  });

  testWidgets('fully onboarded -> home with four tabs and server status', (
    tester,
  ) async {
    await pumpApp(
      tester,
      World(signedIn: true, status: _done, displayName: 'Asha'),
    );

    for (final label in ['Home', 'History', 'Hospitals', 'Profile']) {
      expect(inNavBar(label), findsOneWidget, reason: 'tab $label');
    }
    expect(find.text('Connected to AskMedi server'), findsOneWidget);
    expect(find.text('Hello, Asha!'), findsOneWidget);
  });

  testWidgets('home greets without a name when the profile has none', (
    tester,
  ) async {
    await pumpApp(tester, World(signedIn: true, status: _done));

    expect(find.text('Hello!'), findsOneWidget);
  });

  testWidgets('History and Hospitals tabs use localised titles (Hindi)', (
    tester,
  ) async {
    await pumpApp(
      tester,
      World(signedIn: true, status: _done),
      prefs: const {'app_locale': 'hi'},
    );
    final hi = lookupAppLocalizations(const Locale('hi'));

    await tester.tap(inNavBar(hi.tabHistory));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(hi.tabHistory),
      ),
      findsOneWidget,
    );
    expect(find.text(hi.timelineTab), findsOneWidget);
    expect(find.text(hi.historyEmpty), findsOneWidget);

    await tester.tap(inNavBar(hi.tabHospitals));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(hi.tabHospitals),
      ),
      findsOneWidget,
    );
    expect(find.text(hi.useMyLocation), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(find.text('Hospitals'), findsNothing);
  });

  testWidgets('Home actions open chat, emergency and the Hospitals tab', (
    tester,
  ) async {
    await pumpApp(tester, World(signedIn: true, status: _done));

    await tester.tap(find.text('Check symptoms'));
    await tester.pumpAndSettle();
    expect(locationOf(tester), Routes.chat);
    expect(find.textContaining('AI assistant'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Emergency'));
    await tester.pumpAndSettle();
    expect(locationOf(tester), Routes.emergency);
    expect(find.text('Call 112 — Emergency'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find hospital'));
    await tester.pumpAndSettle();
    expect(locationOf(tester), Routes.hospitals);
    expect(find.text('Use my location'), findsOneWidget);
  });

  testWidgets('delete account: confirm -> RPC -> signed out', (tester) async {
    final world = World(signedIn: true, status: _done);
    await pumpApp(tester, world);

    await tester.tap(inNavBar('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account and all data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);

    // Cancel does nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(world.account.deletes, 0);

    await tester.tap(find.text('Delete account and all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(world.account.deletes, 1);
    expect(find.text('Sign in to AskMedi'), findsOneWidget);
  });

  testWidgets('onboarding advances: consent -> profile -> home', (
    tester,
  ) async {
    final world = World(signedIn: true, status: _none, displayName: 'Asha');
    await pumpApp(tester, world);
    expect(find.text('Before we begin'), findsOneWidget);

    await tester.tap(find.text('I am 18 years or older'));
    await tester.tap(
      find.text('I understand AskMedi is not a doctor and I accept the terms'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Agree and continue'));
    await tester.pumpAndSettle();

    expect(world.consent.saved?[ConsentPurpose.age18Plus], isTrue);
    expect(find.text('Your health profile'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Birth year'),
      '1995',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save and continue'));
    await tester.pumpAndSettle();

    expect(world.profile.saved?.birthYear, 1995);
    expect(world.profile.savedLanguage, 'en');
    expect(inNavBar('Home'), findsOneWidget);
    expect(find.text('Hello, Asha!'), findsOneWidget);
  });

  testWidgets('sign out from the Profile tab returns to sign in', (
    tester,
  ) async {
    await pumpApp(tester, World(signedIn: true, status: _done));

    await tester.tap(inNavBar('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to AskMedi'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('OAuth deep-link route: onboarded user lands on home, no error '
      'page', (tester) async {
    await pumpApp(tester, World(signedIn: true, status: _done));

    routerOf(tester).go(Routes.loginCallback);
    await tester.pumpAndSettle();

    expect(locationOf(tester), Routes.home);
    expect(inNavBar('Home'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('onboarding fetch fails -> splash error with Retry; Retry '
      'recovers', (tester) async {
    final world = World(
      signedIn: true,
      status: _done,
      fetchError: Exception('network down'),
    );
    await pumpApp(tester, world);

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    world.onboarding.error = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(world.onboarding.fetches, 2);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    expect(inNavBar('Home'), findsOneWidget);
    expect(find.text('Connected to AskMedi server'), findsOneWidget);
  });

  testWidgets('failed refetch after saving consent -> splash error + Retry, '
      'not back to consent; Retry moves on to profile', (tester) async {
    final world = World(signedIn: true, status: _none);
    await pumpApp(tester, world);
    expect(find.text('Before we begin'), findsOneWidget);

    // The save itself succeeds, but the refetch that follows it fails.
    world.onboarding.error = Exception('network down');
    await tester.tap(find.text('I am 18 years or older'));
    await tester.tap(
      find.text('I understand AskMedi is not a doctor and I accept the terms'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Agree and continue'));
    await tester.pumpAndSettle();

    expect(world.consent.saved?[ConsentPurpose.age18Plus], isTrue);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Before we begin'), findsNothing);

    world.onboarding.error = null; // now: consents given, profile missing
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong. Please try again.'), findsNothing);
    expect(find.text('Your health profile'), findsOneWidget);
    expect(find.text('Before we begin'), findsNothing);
  });

  testWidgets('returning signed-in user never sees the sign-in screen on '
      'cold start', (tester) async {
    // Supabase reports the persisted session synchronously (isSignedIn) but
    // its auth stream only emits later; the fake mirrors that: isSignedIn is
    // true, watchSignedIn() has not emitted anything.
    final world = World(signedIn: true, status: _done, displayName: 'Asha');
    await pumpApp(tester, world, settle: false);
    expect(find.byType(SignInScreen), findsNothing, reason: 'after pumpWidget');

    await tester.pump();
    expect(find.byType(SignInScreen), findsNothing, reason: 'after pump()');
    await tester.pump(Duration.zero);
    expect(find.byType(SignInScreen), findsNothing, reason: 'after pump(0)');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(SignInScreen), findsNothing, reason: 'frame $i');
    }

    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsNothing);
    expect(inNavBar('Home'), findsOneWidget);
    // The status is fetched once, not again when the auth stream catches up.
    expect(world.onboarding.fetches, 1);
  });

  testWidgets('account switch: Home never shows the previous account data', (
    tester,
  ) async {
    final world = World(signedIn: true, status: _done, displayName: 'Asha');
    await pumpApp(tester, world);
    expect(find.text('Hello, Asha!'), findsOneWidget);
    expect(world.meCalls, 1);

    await tester.tap(inNavBar('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to AskMedi'), findsOneWidget);

    // A different user signs in on the same device, without an app restart.
    world.displayName = 'Bela';
    world.auth.setSignedIn(true);
    await tester.pumpAndSettle();

    expect(inNavBar('Home'), findsOneWidget);
    expect(find.text('Hello, Bela!'), findsOneWidget);
    expect(find.text('Hello, Asha!'), findsNothing);
    // The server check is recomputed for the new session, not reused.
    expect(world.meCalls, 2);
  });

  testWidgets('server unreachable: Home shows the error tile and Retry '
      'promptly (no long retry backoff)', (tester) async {
    final world = World(
      signedIn: true,
      status: _done,
      meError: Exception('offline'),
    );
    await pumpApp(tester, world, settle: false);

    // Bounded: 1.5 s of fake time. Riverpod 3's default retry would still be
    // backing off (200 ms, 400 ms, 800 ms, ...) and show only a spinner.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text("Can't reach the server"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(world.meCalls, 1);

    world.meError = null;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Connected to AskMedi server'), findsOneWidget);
    expect(world.meCalls, 2);
  });
}
