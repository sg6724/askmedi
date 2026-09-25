import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_repository.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/consent/consent_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/talk_screen.dart';
import '../../features/emergency/presentation/emergency_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/hospitals/presentation/hospitals_screen.dart';
import '../../features/medicine/presentation/medicine_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/reports/presentation/report_screen.dart';
import '../../features/onboarding/language_screen.dart';
import '../../features/onboarding/intro_controller.dart';
import '../../features/onboarding/welcome_screen.dart';
import '../../features/onboarding/locale_controller.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/profile/onboarding_repository.dart';
import '../../features/profile/profile_setup_screen.dart';
import 'app_status.dart';
import 'routes.dart';

final appStatusProvider = Provider<AppStatus>((ref) {
  final onboardingAsync = ref.watch(onboardingStatusProvider);
  // A failed refetch keeps the previous (stale) value on the AsyncError, so
  // `.value` alone would bounce the user back to a step they already finished.
  // Treat any error as "not loaded": the splash then offers Retry.
  final onboarding = onboardingAsync.hasError ? null : onboardingAsync.value;
  return AppStatus(
    languageChosen: ref.watch(localeControllerProvider) != null,
    introSeen: ref.watch(introSeenProvider),
    // Falls back to the synchronous session until the auth stream emits, so a
    // returning user is never read as signed out on the first frame.
    signedIn: ref.watch(effectiveSignedInProvider),
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
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      // OAuth deep link (com.askmedi.askmedi://login-callback): supabase_flutter
      // consumes the URI itself; this only gives go_router a page to show
      // meanwhile (redirectFor then moves the user on).
      GoRoute(
        path: Routes.loginCallback,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: Routes.consent,
        builder: (_, _) => ConsentScreen(
          onSaved: () => ref.invalidate(onboardingStatusProvider),
        ),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, _) => ProfileSetupScreen(
          onSaved: () => ref.invalidate(onboardingStatusProvider),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                builder: (_, _) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.hospitals,
                builder: (_, _) => const HospitalsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: Routes.chat, builder: (_, _) => const ChatScreen()),
      GoRoute(path: Routes.talk, builder: (_, _) => const TalkScreen()),
      GoRoute(
        path: Routes.emergency,
        builder: (_, state) => EmergencyScreen(
          args: state.extra is EmergencyArgs
              ? state.extra! as EmergencyArgs
              : const EmergencyArgs(),
        ),
      ),
      GoRoute(path: Routes.medicine, builder: (_, _) => const MedicineScreen()),
      GoRoute(path: Routes.report, builder: (_, _) => const ReportScreen()),
      GoRoute(
        path: Routes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
    ],
  );
});
