import 'package:askmedi/features/consent/consent_purpose.dart';
import 'package:askmedi/features/consent/consent_repository.dart';
import 'package:askmedi/features/consent/consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

class FakeConsentRepository implements ConsentRepository {
  Map<ConsentPurpose, bool>? saved;
  @override
  Future<void> save(Map<ConsentPurpose, bool> choices) async => saved = choices;
}

Finder agreeButton() => find.widgetWithText(FilledButton, 'Agree and continue');

void main() {
  testWidgets('continue is disabled until both required boxes are ticked', (
    tester,
  ) async {
    // Tall viewport so the whole (lazily built) list, including the button, exists.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakeConsentRepository();
    await pumpLocalized(
      tester,
      ConsentScreen(onSaved: () {}),
      overrides: [consentRepositoryProvider.overrideWithValue(fake)],
    );

    expect(tester.widget<FilledButton>(agreeButton()).onPressed, isNull);

    await tester.tap(find.text('I am 18 years or older'));
    await tester.pump();
    expect(tester.widget<FilledButton>(agreeButton()).onPressed, isNull);

    await tester.tap(
      find.text('I understand AskMedi is not a doctor and I accept the terms'),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(agreeButton()).onPressed, isNotNull);
  });

  testWidgets('saves every purpose, optional ones default to false', (
    tester,
  ) async {
    final fake = FakeConsentRepository();
    var savedCalled = false;
    await pumpLocalized(
      tester,
      ConsentScreen(onSaved: () => savedCalled = true),
      overrides: [consentRepositoryProvider.overrideWithValue(fake)],
    );

    await tester.tap(find.text('I am 18 years or older'));
    await tester.tap(
      find.text('I understand AskMedi is not a doctor and I accept the terms'),
    );
    // ListView builds lazily: scroll until the widget exists before tapping it.
    await tester.scrollUntilVisible(
      find.text('Use my location to find nearby hospitals'),
      200,
    );
    await tester.tap(find.text('Use my location to find nearby hospitals'));
    await tester.pump();
    await tester.scrollUntilVisible(agreeButton(), 200);
    await tester.tap(agreeButton());
    await tester.pumpAndSettle();

    expect(fake.saved, {
      ConsentPurpose.age18Plus: true,
      ConsentPurpose.terms: true,
      ConsentPurpose.history: false,
      ConsentPurpose.media: false,
      ConsentPurpose.voice: false,
      ConsentPurpose.location: true,
    });
    expect(savedCalled, isTrue);
  });
}
