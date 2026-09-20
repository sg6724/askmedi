import 'package:askmedi/core/providers.dart';
import 'package:askmedi/features/profile/health_profile.dart';
import 'package:askmedi/features/profile/profile_repository.dart';
import 'package:askmedi/features/profile/profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

class _SavedCall {
  _SavedCall(this.profile, this.language);
  final HealthProfile profile;
  final String language;
}

class _FakeProfileRepository implements ProfileRepository {
  final calls = <_SavedCall>[];

  @override
  Future<void> saveOnboardingProfile(
    HealthProfile profile, {
    required String language,
  }) async {
    calls.add(_SavedCall(profile, language));
  }
}

void main() {
  late _FakeProfileRepository repo;
  late int saved;

  setUp(() {
    repo = _FakeProfileRepository();
    saved = 0;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Map<String, Object> prefsValues = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    await pumpLocalized(
      tester,
      ProfileSetupScreen(onSaved: () => saved++),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        profileRepositoryProvider.overrideWithValue(repo),
      ],
    );
  }

  Future<void> enterBirthYear(WidgetTester tester, String year) async {
    await tester.enterText(
        find.widgetWithText(TextField, 'Birth year'), year);
    await tester.pump();
  }

  testWidgets('an under-18 birth year shows the adults-only error and does not save',
      (tester) async {
    await pumpScreen(tester);

    await enterBirthYear(tester, '2012');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(find.text('AskMedi is only for adults (18+)'), findsOneWidget);
    expect(repo.calls, isEmpty);
    expect(saved, 0);
  });

  testWidgets('a valid year saves with the app locale and calls onSaved',
      (tester) async {
    await pumpScreen(tester, prefsValues: {'app_locale': 'hi'});

    await enterBirthYear(tester, '1995');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.profile.birthYear, 1995);
    expect(repo.calls.single.language, 'hi');
    expect(saved, 1);
  });

  testWidgets('the pregnancy question appears only after choosing Female',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Are you currently pregnant?'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Male'));
    await tester.pumpAndSettle();
    expect(find.text('Are you currently pregnant?'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Female'));
    await tester.pumpAndSettle();
    expect(find.text('Are you currently pregnant?'), findsOneWidget);
  });

  Finder chipField(String label) => find.widgetWithText(TextField, label);

  testWidgets('pending condition text is saved without pressing Enter',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
        chipField('Known conditions (e.g. diabetes)'), 'Diabetes');
    await enterBirthYear(tester, '1995');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.profile.conditions, ['Diabetes']);
    expect(saved, 1);
  });

  testWidgets('pending medicine and allergy text are saved without pressing Enter',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
        chipField('Known conditions (e.g. diabetes)'), 'Diabetes');
    await tester.enterText(
        chipField('Medicines you take regularly'), 'Metformin');
    await tester.enterText(chipField('Allergies'), 'Penicillin');
    await enterBirthYear(tester, '1995');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    final profile = repo.calls.single.profile;
    expect(profile.conditions, ['Diabetes']);
    expect(profile.medicines, ['Metformin']);
    expect(profile.allergies, ['Penicillin']);
  });

  testWidgets('tapping the add icon adds a chip and clears the field',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
        chipField('Known conditions (e.g. diabetes)'), 'Diabetes');
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Diabetes'), findsOneWidget);
    final field = tester.widget<TextField>(
        chipField('Known conditions (e.g. diabetes)'));
    expect(field.controller!.text, isEmpty);
  });
}
