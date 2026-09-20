import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';

abstract interface class AuthRepository {
  bool get isSignedIn;
  Stream<bool> watchSignedIn();
  Future<void> signInWithGoogle();
  Future<void> sendEmailOtp(String email);
  Future<void> verifyEmailOtp({required String email, required String code});
  Future<void> signOut();
  Future<String?> accessToken();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  static const redirectUrl = 'com.askmedi.askmedi://login-callback';
  final SupabaseClient _client;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Stream<bool> watchSignedIn() =>
      _client.auth.onAuthStateChange.map((event) => event.session != null);

  @override
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectUrl,
    );
  }

  @override
  Future<void> sendEmailOtp(String email) =>
      _client.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<String?> accessToken() async =>
      _client.auth.currentSession?.accessToken;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final signedInProvider = StreamProvider<bool>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.isSignedIn;
  yield* repo.watchSignedIn();
});

/// Whether a user is signed in, usable from the very first frame.
///
/// Supabase knows the persisted session synchronously ([AuthRepository.isSignedIn])
/// but [signedInProvider]'s stream only emits later. Until it has a value, trust
/// the synchronous session so a returning user is not treated as signed out (and
/// shown the sign-in screen) on cold start; any later stream value, including
/// `false`, wins. Never throws while the stream is loading or errored.
///
/// A plain `Provider<bool>` only notifies dependents when the value changes, so
/// the stream catching up with the same answer does not rebuild (or refetch)
/// anything downstream.
final effectiveSignedInProvider = Provider<bool>((ref) {
  final streamed = ref.watch(signedInProvider).value;
  return streamed ?? ref.read(authRepositoryProvider).isSignedIn;
});
