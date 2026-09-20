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
    Size viewport = const Size(1080, 3000),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

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

  testWidgets('pending text that duplicates a chip, or is blank, is not added',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(
        chipField('Known conditions (e.g. diabetes)'), 'Diabetes');
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        chipField('Known conditions (e.g. diabetes)'), '  Diabetes ');
    await tester.enterText(chipField('Allergies'), '   ');
    await enterBirthYear(tester, '1995');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.profile.conditions, ['Diabetes']);
    expect(repo.calls.single.profile.allergies, isEmpty);
  });

  testWidgets(
      'pending text survives its field being scrolled out of the lazy list',
      (tester) async {
    // Tiny viewport + 3x text: the ListView builds lazily, so an unfocused chip
    // field scrolled beyond the cache extent (250 px) is disposed with its State.
    await pumpScreen(tester,
        viewport: const Size(360, 320), textScale: 3.0);
    final conditions = chipField('Known conditions (e.g. diabetes)');
    final scrollable = find.byType(Scrollable).first;

    // At this size even the year field starts below the cache extent.
    await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Birth year'), 100,
        scrollable: scrollable);
    await enterBirthYear(tester, '1995');
    await tester.scrollUntilVisible(conditions, 100, scrollable: scrollable);
    await tester.enterText(conditions, 'Diabetes');
    // A focused EditableText keeps itself alive when scrolled away. The user
    // dismissing the keyboard / tapping elsewhere drops that focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.scrollUntilVisible(
        find.text('Save and continue'), 100, scrollable: scrollable);
    await tester.pumpAndSettle();

    // Prove the premise: the conditions field really is gone from the tree.
    expect(
        find.widgetWithText(
            TextField, 'Known conditions (e.g. diabetes)', skipOffstage: false),
        findsNothing);

    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.profile.conditions, ['Diabetes']);
    expect(saved, 1);
  });
}
