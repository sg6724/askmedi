import 'package:askmedi/core/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

void main() {
  const taglines = {
    'en': 'Your Health, Our Concern',
    'hi': 'आपका स्वास्थ्य, हमारी चिंता',
    'mr': 'तुमचे आरोग्य, आमची काळजी',
  };

  for (final entry in taglines.entries) {
    testWidgets('loads ${entry.key} localisation', (tester) async {
      await pumpLocalized(
        tester,
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Column(
              children: [Text(l10n.appTitle), Text(l10n.tagline)],
            );
          },
        ),
        locale: Locale(entry.key),
      );

      expect(find.text('AskMedi'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
    });
  }
}
