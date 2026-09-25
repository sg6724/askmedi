import 'package:askmedi/core/l10n/gen/app_localizations.dart';
import 'package:askmedi/core/platform/url_opener.dart';
import 'package:askmedi/core/routing/routes.dart';
import 'package:askmedi/core/theme/app_theme.dart';
import 'package:askmedi/features/emergency/presentation/emergency_screen.dart';
import 'package:askmedi/features/onboarding/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Records links instead of launching them.
class RecordingOpener {
  final opened = <Uri>[];
  Future<bool> call(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

/// Pumps [screen] under a real GoRouter with stand-ins for the routes it can
/// navigate to (Emergency is the real screen; Hospitals is a marker).
Future<GoRouter> pumpRouted(
  WidgetTester tester,
  Widget screen, {
  List overrides = const [],
  RecordingOpener? opener,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      GoRoute(
        path: Routes.emergency,
        builder: (_, state) => EmergencyScreen(
            args: state.extra is EmergencyArgs
                ? state.extra! as EmergencyArgs
                : const EmergencyArgs()),
      ),
      GoRoute(
          path: Routes.hospitals,
          builder: (_, _) => const Scaffold(body: Text('HOSPITALS TAB'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      urlOpenerProvider.overrideWithValue((opener ?? RecordingOpener()).call),
      appLanguageProvider.overrideWithValue('en'),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: buildAppTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}
