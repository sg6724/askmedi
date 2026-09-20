import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_repository.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/consent/consent_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/placeholder_tab.dart';
import '../../features/home/profile_tab.dart';
import '../../features/onboarding/language_screen.dart';
import '../../features/onboarding/locale_controller.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/profile/onboarding_repository.dart';
import '../../features/profile/profile_setup_screen.dart';
import '../l10n/gen/app_localizations.dart';
import 'app_status.dart';
import 'routes.dart';

final appStatusProvider = Provider<AppStatus>((ref) {
  final onboarding = ref.watch(onboardingStatusProvider).value;
  return AppStatus(
    languageChosen: ref.watch(localeControllerProvider) != null,
    signedIn: ref.watch(signedInProvider).value ?? false,
    onboardingLoaded: onboarding != null,
    consentsGiven: onboarding?.consentsGiven ?? false,
    profileComplete: onboarding?.profileComplete ?? false,
  );
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(appStatusProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectFor(ref.read(appStatusProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.language, builder: (_, _) => const LanguageScreen()),
      // OAuth deep link (com.askmedi.askmedi://login-callback): supabase_flutter
      // consumes the URI itself; this only gives go_router a page to show
      // meanwhile (redirectFor then moves the user on).
      GoRoute(
          path: Routes.loginCallback, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.signIn,
        builder: (context, _) => SignInScreen(
          // The email travels in `extra`, not in the URL (no PII in the URI).
          onCodeSent: (email) => context.push(Routes.otp, extra: email),
        ),
        routes: [
          GoRoute(
            path: 'otp',
            builder: (_, state) =>
                OtpScreen(email: state.extra as String? ?? ''),
          ),
        ],
      ),
      GoRoute(
        path: Routes.consent,
        builder: (_, _) => ConsentScreen(
            onSaved: () => ref.invalidate(onboardingStatusProvider)),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, _) => ProfileSetupScreen(
            onSaved: () => ref.invalidate(onboardingStatusProvider)),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.history,
                builder: (context, _) => PlaceholderTab(
                    title: AppLocalizations.of(context).tabHistory)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.hospitals,
                builder: (context, _) => PlaceholderTab(
                    title: AppLocalizations.of(context).tabHospitals)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const ProfileTab()),
          ]),
        ],
      ),
    ],
  );
});
