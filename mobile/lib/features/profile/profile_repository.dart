import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'health_profile.dart';

abstract interface class ProfileRepository {
  /// FIRST-TIME ONBOARDING ONLY. Deletes and re-inserts the condition, medicine
  /// and allergy lists non-atomically (the profile row, with
  /// `onboarding_completed_at`, is written last). A dropped connection midway
  /// would leave the lists wiped or partly rewritten, which is harmless for a
  /// first-time flow but not for editing stored data. A later profile-EDIT flow
  /// must not reuse this: use a transactional RPC (e.g. `replace_health_profile`)
  /// or insert-then-delete instead.
  Future<void> saveOnboardingProfile(HealthProfile profile, {required String language});
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> saveOnboardingProfile(
    HealthProfile p, {
    required String language,
  }) async {
    final userId = _client.auth.currentUser!.id;

    // Child lists first; the profile row (with onboarding_completed_at) is written
    // last so a partial failure never marks onboarding as complete.
    for (final table in ['health_conditions', 'user_medicines', 'allergies']) {
      await _client.from(table).delete().eq('user_id', userId);
    }
    if (p.conditions.isNotEmpty) {
      await _client
          .from('health_conditions')
          .insert([for (final c in p.conditions) {'name': c}]);
    }
    if (p.medicines.isNotEmpty) {
      await _client
          .from('user_medicines')
          .insert([for (final m in p.medicines) {'salt': m}]);
    }
    if (p.allergies.isNotEmpty) {
      await _client
          .from('allergies')
          .insert([for (final a in p.allergies) {'substance': a}]);
    }

    await _client.from('profiles').upsert({
      'user_id': userId,
      'display_name': p.displayName,
      'language': language,
      'birth_year': p.birthYear,
      'sex': p.sex?.wire,
      'pregnant': p.sex == Sex.female ? p.pregnant : null,
      'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);
