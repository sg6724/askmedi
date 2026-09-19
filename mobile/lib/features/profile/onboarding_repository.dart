import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../auth/auth_repository.dart';
import '../consent/consent_purpose.dart';

class OnboardingStatus {
  const OnboardingStatus({required this.consentsGiven, required this.profileComplete});
  final bool consentsGiven;
  final bool profileComplete;
}

abstract interface class OnboardingRepository {
  Future<OnboardingStatus> fetch();
}

class SupabaseOnboardingRepository implements OnboardingRepository {
  SupabaseOnboardingRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<OnboardingStatus> fetch() async {
    final rows = await _client.from('current_consents').select('purpose, granted');
    final granted = {
      for (final r in rows) r['purpose'] as String: r['granted'] as bool,
    };
    final consentsGiven = ConsentPurpose.values
        .where((p) => p.required)
        .every((p) => granted[p.wire] == true);

    final profile = await _client
        .from('profiles')
        .select('onboarding_completed_at')
        .maybeSingle();
    final profileComplete =
        profile != null && profile['onboarding_completed_at'] != null;

    return OnboardingStatus(
        consentsGiven: consentsGiven, profileComplete: profileComplete);
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => SupabaseOnboardingRepository(ref.watch(supabaseClientProvider)),
);

/// null while signed out. Invalidate after saving consents or the profile.
final onboardingStatusProvider = FutureProvider<OnboardingStatus?>((ref) async {
  final signedIn = ref.watch(signedInProvider).value ?? false;
  if (!signedIn) return null;
  return ref.watch(onboardingRepositoryProvider).fetch();
});
