import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'health_profile.dart';

abstract interface class ProfileRepository {
  /// FIRST-TIME ONBOARDING ONLY. Deletes and re-inserts the condition, medicine
  /// and allergy lists non-atomically (the profile row, with
  /// `onboarding_completed_at`, is written last). A dropped connection midway
  /// would leave the lists wiped or partly rewritten, which is harmless for a
  /// first-time flow but not for editing stored data. Editing uses
  /// [updateProfile] instead.
  Future<void> saveOnboardingProfile(HealthProfile profile, {required String language});

  /// The stored profile, or null if there is none yet.
  Future<HealthProfile?> loadProfile();

  /// Profile EDIT: new list rows are inserted before the old ones are deleted,
  /// so a dropped connection can leave duplicates but never wipes the lists.
  Future<void> updateProfile(HealthProfile profile, {required String language});
}

/// The profile's free-text lists: table and the column holding the text.
const _lists = [
  ('health_conditions', 'name'),
  ('user_medicines', 'salt'),
  ('allergies', 'substance'),
];

List<String> _itemsFor(HealthProfile p, String table) => switch (table) {
      'health_conditions' => p.conditions,
      'user_medicines' => p.medicines,
      _ => p.allergies,
    };

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

  @override
  Future<HealthProfile?> loadProfile() async {
    final row = await _client
        .from('profiles')
        .select('display_name, birth_year, sex, pregnant')
        .maybeSingle();
    if (row == null) return null;
    final lists = <String, List<String>>{};
    for (final (table, column) in _lists) {
      final rows = await _client.from(table).select(column).order('created_at');
      lists[table] = [for (final r in rows) r[column] as String];
    }
    return HealthProfile(
      displayName: row['display_name'] as String?,
      birthYear: (row['birth_year'] as int?) ?? 0,
      sex: Sex.values.where((s) => s.wire == row['sex']).firstOrNull,
      pregnant: row['pregnant'] as bool?,
      conditions: lists['health_conditions']!,
      medicines: lists['user_medicines']!,
      allergies: lists['allergies']!,
    );
  }

  @override
  Future<void> updateProfile(HealthProfile p, {required String language}) async {
    final userId = _client.auth.currentUser!.id;
    for (final (table, column) in _lists) {
      final old = await _client.from(table).select('id');
      final items = _itemsFor(p, table);
      if (items.isNotEmpty) {
        await _client.from(table).insert([for (final i in items) {column: i}]);
      }
      final oldIds = [for (final r in old) r['id'] as String];
      if (oldIds.isNotEmpty) {
        await _client.from(table).delete().inFilter('id', oldIds);
      }
    }
    await _client.from('profiles').update({
      'display_name': p.displayName,
      'language': language,
      'birth_year': p.birthYear,
      'sex': p.sex?.wire,
      'pregnant': p.sex == Sex.female ? p.pregnant : null,
    }).eq('user_id', userId);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);
