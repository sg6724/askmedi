import 'package:askmedi/features/auth/auth_repository.dart';
import 'package:askmedi/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

class FakeAuthRepository implements AuthRepository {
  final signIns = <String>[];
  final signUps = <String>[];
  int googleCalls = 0;
  AuthFailure? failWith;
  bool signUpSignsIn = true;

  @override
  bool get isSignedIn => false;
  @override
  Stream<bool> watchSignedIn() => const Stream.empty();
  @override
  Future<void> signInWithGoogle() async => googleCalls++;
  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    signIns.add(email);
  }

  @override
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    signUps.add(email);
    return signUpSignsIn;
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<String?> accessToken() async => null;
}

Future<FakeAuthRepository> _pump(
  WidgetTester tester, [
  FakeAuthRepository? fake,
]) async {
  final repo = fake ?? FakeAuthRepository();
  await pumpLocalized(
    tester,
    const SignInScreen(),
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return repo;
}

Future<void> _fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Email address'),
    email,
  );
  await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
}

void main() {
  testWidgets('invalid email and short password show errors, call nothing', (
    tester,
  ) async {
    final fake = await _pump(tester);
    await _fill(tester, 'not-an-email', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(fake.signIns, isEmpty);
  });

  testWidgets('valid credentials sign in', (tester) async {
    final fake = await _pump(tester);
    await _fill(tester, 'priya@example.com', 'correct-horse');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(fake.signIns, ['priya@example.com']);
  });

  testWidgets('wrong password shows a friendly error', (tester) async {
    final fake = await _pump(
      tester,
      FakeAuthRepository()
        ..failWith = const AuthFailure(AuthFailureKind.invalidCredentials),
    );
    await _fill(tester, 'priya@example.com', 'wrong-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong email or password'), findsOneWidget);
    expect(fake.signIns, isEmpty);
  });

  testWidgets('create account', (tester) async {
    final fake = await _pump(tester);
    await _fill(tester, 'priya@example.com', 'correct-horse');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(fake.signUps, ['priya@example.com']);
  });

  testWidgets('create account when confirmation is required tells the user', (
    tester,
  ) async {
    await _pump(tester, FakeAuthRepository()..signUpSignsIn = false);
    await _fill(tester, 'priya@example.com', 'correct-horse');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Account created. Confirm your email, then sign in.'),
      findsOneWidget,
    );
  });

  testWidgets('existing email on create account says so', (tester) async {
    await _pump(
      tester,
      FakeAuthRepository()
        ..failWith = const AuthFailure(AuthFailureKind.emailTaken),
    );
    await _fill(tester, 'priya@example.com', 'correct-horse');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email already exists. Please sign in.'),
      findsOneWidget,
    );
  });

  testWidgets('Google button starts OAuth', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(fake.googleCalls, 1);
  });

  test('AuthFailure maps Supabase error codes', () {
    expect(
      AuthFailure.fromCode('invalid_credentials').kind,
      AuthFailureKind.invalidCredentials,
    );
    expect(
      AuthFailure.fromCode('user_already_exists').kind,
      AuthFailureKind.emailTaken,
    );
    expect(
      AuthFailure.fromCode('email_exists').kind,
      AuthFailureKind.emailTaken,
    );
    expect(
      AuthFailure.fromCode('weak_password').kind,
      AuthFailureKind.weakPassword,
    );
    expect(AuthFailure.fromCode(null).kind, AuthFailureKind.other);
  });
}
