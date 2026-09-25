// Live end-to-end test of the app's real data layer against the deployed services
// (Supabase Auth + Postgres, the Vercel backend, Gemini/Groq, ElevenLabs, OSM).
//
// Kept out of test/ on purpose: it needs the network and a throwaway account.
// Run (see test_live/README.md):
//   flutter test test_live --dart-define-from-file=env/dev.json \
//     --dart-define=E2E_EMAIL=... --dart-define=E2E_PASSWORD=... \
//     --dart-define=E2E_LAB_PDF=path/to/lab.pdf --dart-define=E2E_STRIP_IMAGE=path/to/strip.png
import 'dart:io';

import 'package:askmedi/core/config/app_config.dart';
import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/features/auth/auth_repository.dart';
import 'package:askmedi/features/chat/data/chat_repository.dart';
import 'package:askmedi/features/chat/data/voice_repository.dart';
import 'package:askmedi/features/chat/domain/chat_models.dart';
import 'package:askmedi/features/consent/consent_purpose.dart';
import 'package:askmedi/features/consent/consent_repository.dart';
import 'package:askmedi/features/history/data/history_repository.dart';
import 'package:askmedi/features/hospitals/data/hospitals_repository.dart';
import 'package:askmedi/features/hospitals/domain/hospital.dart';
import 'package:askmedi/features/medicine/data/medicine_repository.dart';
import 'package:askmedi/features/profile/data/account_repository.dart';
import 'package:askmedi/features/profile/health_profile.dart';
import 'package:askmedi/features/profile/onboarding_repository.dart';
import 'package:askmedi/features/profile/profile_repository.dart';
import 'package:askmedi/features/reports/data/report_repository.dart';
import 'package:askmedi/features/reports/domain/report_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _email = String.fromEnvironment('E2E_EMAIL');
const _password = String.fromEnvironment('E2E_PASSWORD');
const _labPdf = String.fromEnvironment('E2E_LAB_PDF');
const _stripImage = String.fromEnvironment('E2E_STRIP_IMAGE');

void log(String step, Object detail) => print('E2E  $step: $detail');

void main() {
  late SupabaseClient db;
  late ApiClient api;
  late SupabaseAuthRepository auth;

  setUpAll(() {
    if (_email.isEmpty || AppConfig.supabaseUrl.isEmpty) {
      fail('Missing --dart-define values (see file header).');
    }
    db = SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    auth = SupabaseAuthRepository(db);
    api = ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: auth.accessToken);
  });

  test('1 sign in with email + password', () async {
    await expectLater(
      auth.signInWithPassword(email: _email, password: 'wrong-password'),
      throwsA(isA<AuthFailure>()
          .having((f) => f.kind, 'kind', AuthFailureKind.invalidCredentials)),
    );
    await auth.signInWithPassword(email: _email, password: _password);
    expect(auth.isSignedIn, isTrue);
    final me = await api.getMe();
    log('signed in, /me user', me.userId);
  });

  test('2 onboarding: consent + health profile', () async {
    final onboarding = SupabaseOnboardingRepository(db);
    expect((await onboarding.fetch()).consentsGiven, isFalse);
    await SupabaseConsentRepository(db)
        .save({for (final p in ConsentPurpose.values) p: true});
    await SupabaseProfileRepository(db).saveOnboardingProfile(
      const HealthProfile(
        birthYear: 1995,
        displayName: 'E2E Tester',
        sex: Sex.female,
        pregnant: false,
        conditions: ['Liver disease'],
        allergies: ['Penicillin'],
      ),
      language: 'en',
    );
    final status = await onboarding.fetch();
    expect(status.consentsGiven, isTrue);
    expect(status.profileComplete, isTrue);
    final profile = await SupabaseProfileRepository(db).loadProfile();
    expect(profile!.conditions, contains('Liver disease'));
    log('onboarding', 'consents + profile saved and read back');
  });

  test('3 chat: emergency in Hindi (romanised, extra words)', () async {
    final reply = await ApiChatRepository(api).send(
        episodeId: null, message: 'mujhe seene mein bahut dard ho raha hai', language: 'hi');
    log('emergency', '${reply.type.name} ${reply.emergency?.ruleId} call=${reply.emergency?.call}');
    expect(reply.type, ChatReplyType.emergency);
    expect(reply.emergency!.call, contains('112'));
  });

  test('4 chat: follow-ups until an answer (Marathi)', () async {
    final chat = ApiChatRepository(api);
    var reply = await chat.send(
        episodeId: null, message: 'मला दोन दिवसांपासून ताप आणि अंगदुखी आहे', language: 'mr');
    var turns = 1;
    while (reply.type == ChatReplyType.followup && turns < 5) {
      log('followup $turns', '${reply.followup?.question} ${reply.followup?.options}');
      reply = await chat.send(
          episodeId: reply.episodeId, message: reply.followup!.options.first, language: 'mr');
      turns++;
    }
    log('answer', '${reply.type.name} urgency=${reply.answer?.urgency?.name} '
        'causes=${reply.answer?.causes.map((c) => '${c.name}/${c.likelihood.name}').toList()} '
        'sources=${reply.sources.length}');
    expect(reply.type, ChatReplyType.answer);
    expect(reply.answer!.causes, isNotEmpty);
    expect(reply.sources, isNotEmpty);
    expect(reply.disclaimer, isNotEmpty);
  });

  test('5 medicine: scan a strip photo, then look it up', () async {
    final medicine = ApiMedicineRepository(api);
    if (_stripImage.isNotEmpty) {
      final bytes = await File(_stripImage).readAsBytes();
      final candidates = await medicine
          .scan(UploadFile(bytes: bytes, name: 'strip.png', mimeType: 'image/png'));
      log('scan', candidates.map((c) => '${c.brand} ${c.salts.map((s) => s.name)}').toList());
      expect(candidates, isNotEmpty);
    }
    final info = await medicine.lookup(name: 'Paracetamol', brand: 'Crocin 500', language: 'en');
    log('lookup', 'uses=${info.uses.length} flags=${info.pharmacistFlags} sources=${info.sources.length}');
    expect(info.uses, isNotEmpty);
    expect(info.pharmacistFlags.join(' ').toLowerCase(), contains('liver'));
  });

  test('6 report: parse PDF, confirm, trend history', () async {
    final reports = ApiReportRepository(api, db);
    final bytes = await File(_labPdf).readAsBytes();
    final parsed =
        await reports.parse(UploadFile(bytes: bytes, name: 'lab.pdf', mimeType: 'application/pdf'));
    log('parse', parsed.values.map((v) => '${v.testName}=${v.value} ${v.status.name}').toList());
    expect(parsed.values, isNotEmpty);
    final summary = await reports.confirm(parsed.reportId, parsed.values, language: 'hi');
    log('confirm', summary.summary.length > 80 ? '${summary.summary.substring(0, 80)}…' : summary.summary);
    final points = await reports.history(parsed.values.first.testName);
    log('trend points', points.length);
    expect(points, isNotEmpty);
  });

  test('7 hospitals by PIN code and by area', () async {
    final hospitals = ApiHospitalsRepository(api);
    final byPin = await hospitals.search(HospitalQuery.fromText('411001'));
    log('PIN 411001', '${byPin.hospitals.length} found, first=${byPin.hospitals.first.name}');
    expect(byPin.hospitals, isNotEmpty);
    final byArea = await hospitals.search(HospitalQuery.fromText('Kothrud, Pune'));
    log('Kothrud', '${byArea.hospitals.length} found');
    expect(byArea.hospitals, isNotEmpty);
  });

  test('8 voice: speak Hindi, transcribe it back', () async {
    final voice = ApiVoiceRepository(api);
    final audio = await voice.speak('मुझे दो दिन से बुखार है', language: 'hi');
    log('speak', '${audio.length} bytes');
    expect(audio.length, greaterThan(1000));
  });

  test('9 history + analytics data', () async {
    final history = await SupabaseHistoryRepository(db).load();
    log('history', 'episodes=${history.episodes.length} medicines=${history.medicines.length} '
        'reports=${history.reports.length} tests=${history.values.keys.toList()}');
    expect(history.episodes, isNotEmpty);
    expect(history.medicines, isNotEmpty);
    expect(history.reports, isNotEmpty);
  });

  test('10 delete account and all data', () async {
    await SupabaseAccountRepository(db).deleteAccount();
    await auth.signOut();
    await expectLater(auth.signInWithPassword(email: _email, password: _password),
        throwsA(isA<AuthFailure>()));
    log('delete', 'account deleted; sign-in now refused');
  });
}
