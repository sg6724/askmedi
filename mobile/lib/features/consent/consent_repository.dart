import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'consent_purpose.dart';

abstract interface class ConsentRepository {
  /// Appends one row per purpose (the consent log is append-only).
  Future<void> save(Map<ConsentPurpose, bool> choices);
}

class SupabaseConsentRepository implements ConsentRepository {
  SupabaseConsentRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> save(Map<ConsentPurpose, bool> choices) async {
    await _client.from('consents').insert([
      for (final e in choices.entries)
        {'purpose': e.key.wire, 'granted': e.value},
    ]);
  }
}

final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => SupabaseConsentRepository(ref.watch(supabaseClientProvider)),
);
