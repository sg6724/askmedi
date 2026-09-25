import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

abstract interface class AccountRepository {
  /// Deletes the user and, by cascade, every row they own.
  Future<void> deleteAccount();
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> deleteAccount() => _client.rpc<void>('delete_my_account');
}

final accountRepositoryProvider = Provider<AccountRepository>(
    (ref) => SupabaseAccountRepository(ref.watch(supabaseClientProvider)));
