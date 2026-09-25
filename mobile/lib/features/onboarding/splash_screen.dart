import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../profile/onboarding_repository.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(onboardingStatusProvider);
    return Scaffold(
      body: Center(
        child: status.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.genericError),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(onboardingStatusProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
