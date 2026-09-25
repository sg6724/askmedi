import 'package:askmedi/features/auth/auth_repository.dart';
import 'package:askmedi/features/profile/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOnboardingRepository implements OnboardingRepository {
  _FakeOnboardingRepository({this.status, this.error});
  final OnboardingStatus? status;
  final Object? error;

  @override
  Future<OnboardingStatus> fetch() async {
    if (error != null) throw error!;
    return status!;
  }
}

/// Waits for [signedInProvider] to emit first: [onboardingStatusProvider] reads
/// it synchronously, so it would otherwise see the loading state as signed out.
Future<ProviderContainer> _container({
  required bool signedIn,
  required OnboardingRepository repo,
}) async {
  final container = ProviderContainer(
    overrides: [
      signedInProvider.overrideWith((ref) => Stream.value(signedIn)),
      onboardingRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  // Riverpod 3 pauses providers that have no listener, so keep both alive.
  container.listen(signedInProvider, (_, _) {});
  container.listen(onboardingStatusProvider, (_, _) {});
  await container.read(signedInProvider.future);
  return container;
}

void main() {
  test(
    'a failing fetch surfaces as an error promptly (no silent retry)',
    () async {
      final container = await _container(
        signedIn: true,
        repo: _FakeOnboardingRepository(error: Exception('network down')),
      );

      await expectLater(
        container.read(onboardingStatusProvider.future),
        throwsA(isA<Exception>()),
      ).timeout(const Duration(seconds: 5));
    },
  );

  test('yields the fetched status when signed in', () async {
    final container = await _container(
      signedIn: true,
      repo: _FakeOnboardingRepository(
        status: const OnboardingStatus(
          consentsGiven: true,
          profileComplete: true,
        ),
      ),
    );

    final status = await container.read(onboardingStatusProvider.future);
    expect(status, isNotNull);
    expect(status!.consentsGiven, isTrue);
    expect(status.profileComplete, isTrue);
  });

  test('is null while signed out', () async {
    final container = await _container(
      signedIn: false,
      repo: _FakeOnboardingRepository(error: Exception('must not be called')),
    );

    expect(await container.read(onboardingStatusProvider.future), isNull);
  });
}
