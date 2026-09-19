import 'package:askmedi/core/providers.dart';
import 'package:askmedi/features/onboarding/language_screen.dart';
import 'package:askmedi/features/onboarding/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows exactly the three languages with script samples',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpLocalized(tester, const LanguageScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);

    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिंदी'), findsOneWidget);
    expect(find.text('मराठी'), findsOneWidget);
  });

  testWidgets('choosing Marathi and continuing persists the locale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpLocalized(tester, const LanguageScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);

    await tester.tap(find.text('मराठी'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(LanguageScreen)));
    expect(container.read(localeControllerProvider), const Locale('mr'));
    expect(prefs.getString('app_locale'), 'mr');
  });
}
