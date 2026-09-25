import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/providers.dart';
import 'package:askmedi/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Real `meProvider` / `displayNameProvider` (no override of the providers
/// themselves), fed by fakes for their data sources.
class _FakeApiClient implements ApiClient {
  _FakeApiClient({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  Future<MeResponse> getMe() async {
    calls++;
    if (fail) throw Exception('offline');
    return const MeResponse(userId: 'u-1');
  }

  // Feature endpoints are not used by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every call (i.e. `from(...)`) fails, like an unreachable Supabase.
class _OfflineSupabase implements SupabaseClient {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw Exception('offline');
  }
}

ProviderContainer _container(List overrides) {
  final container = ProviderContainer(overrides: [...overrides]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('meProvider', () {
    test('a failing call reaches AsyncError promptly, without retrying',
        () async {
      final api = _FakeApiClient(fail: true);
      final container = _container([apiClientProvider.overrideWithValue(api)]);
      container.listen(meProvider, (_, _) {});

      // Riverpod 3's default retry would keep this in AsyncLoading for ~38 s.
      await expectLater(
        container.read(meProvider.future),
        throwsA(isA<Exception>()),
      ).timeout(const Duration(seconds: 2));
      expect(container.read(meProvider).hasError, isTrue);
      expect(api.calls, 1);
    });

    test('is disposed with its last listener (no cross-account cache)',
        () async {
      final api = _FakeApiClient();
      final container = _container([apiClientProvider.overrideWithValue(api)]);

      final sub = container.listen(meProvider, (_, _) {});
      await container.read(meProvider.future);
      expect(container.exists(meProvider), isTrue);

      sub.close();
      await container.pump();
      expect(container.exists(meProvider), isFalse);

      // Listening again (the next account's Home) recomputes.
      container.listen(meProvider, (_, _) {});
      await container.read(meProvider.future);
      expect(api.calls, 2);
    });
  });

  group('displayNameProvider', () {
    test('a failing call reaches AsyncError promptly, without retrying',
        () async {
      final supabase = _OfflineSupabase();
      final container =
          _container([supabaseClientProvider.overrideWithValue(supabase)]);
      container.listen(displayNameProvider, (_, _) {});

      await expectLater(
        container.read(displayNameProvider.future),
        throwsA(isA<Exception>()),
      ).timeout(const Duration(seconds: 2));
      expect(container.read(displayNameProvider).hasError, isTrue);
      expect(supabase.calls, 1);
    });

    test('is disposed with its last listener (no cross-account cache)',
        () async {
      final supabase = _OfflineSupabase();
      final container =
          _container([supabaseClientProvider.overrideWithValue(supabase)]);

      final sub = container.listen(displayNameProvider, (_, _) {});
      await expectLater(
        container.read(displayNameProvider.future),
        throwsA(isA<Exception>()),
      );
      expect(container.exists(displayNameProvider), isTrue);

      sub.close();
      await container.pump();
      expect(container.exists(displayNameProvider), isFalse);
    });
  });
}
