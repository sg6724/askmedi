import 'package:askmedi/features/auth/auth_repository.dart';
import 'package:askmedi/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

class FakeAuthRepository implements AuthRepository {
  final sentTo = <String>[];
  int googleCalls = 0;

  @override
  bool get isSignedIn => false;
  @override
  Stream<bool> watchSignedIn() => const Stream.empty();
  @override
  Future<void> signInWithGoogle() async => googleCalls++;
  @override
  Future<void> sendEmailOtp(String email) async => sentTo.add(email);
  @override
  Future<void> verifyEmailOtp({required String email, required String code}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> accessToken() async => null;
}

void main() {
  testWidgets('invalid email shows error and sends nothing', (tester) async {
    final fake = FakeAuthRepository();
    await pumpLocalized(tester, SignInScreen(onCodeSent: (_) {}),
        overrides: [authRepositoryProvider.overrideWithValue(fake)]);

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(fake.sentTo, isEmpty);
  });

  testWidgets('valid email sends OTP and reports it', (tester) async {
    final fake = FakeAuthRepository();
    String? reported;
    await pumpLocalized(tester, SignInScreen(onCodeSent: (e) => reported = e),
        overrides: [authRepositoryProvider.overrideWithValue(fake)]);

    await tester.enterText(find.byType(TextField), 'priya@example.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(fake.sentTo, ['priya@example.com']);
    expect(reported, 'priya@example.com');
  });

  testWidgets('Google button starts OAuth', (tester) async {
    final fake = FakeAuthRepository();
    await pumpLocalized(tester, SignInScreen(onCodeSent: (_) {}),
        overrides: [authRepositoryProvider.overrideWithValue(fake)]);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(fake.googleCalls, 1);
  });
}
