import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// Per-user data: autoDispose so it is dropped with Home on sign-out and a
/// different account signing in on the same device never sees a cached name.
/// `retry` is off (Riverpod 3 would back off for ~38 s); Home degrades to the
/// name-less greeting instead.
final displayNameProvider = FutureProvider.autoDispose<String?>(
  (ref) async {
    final row = await ref
        .watch(supabaseClientProvider)
        .from('profiles')
        .select('display_name')
        .maybeSingle();
    return row?['display_name'] as String?;
  },
  retry: (_, _) => null,
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final name = ref.watch(displayNameProvider).value;
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle,
            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(name == null ? l10n.greetingNoName : l10n.greeting(name),
              style: Theme.of(context).textTheme.headlineSmall),
          Text(l10n.howCanIHelp,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          me.when(
            data: (_) => ListTile(
              leading: const Icon(Icons.cloud_done, color: AppColors.teal),
              title: Text(l10n.serverConnected),
            ),
            error: (_, _) => ListTile(
              leading: const Icon(Icons.cloud_off, color: AppColors.danger),
              title: Text(l10n.serverUnreachable),
              trailing: TextButton(
                onPressed: () => ref.invalidate(meProvider),
                child: Text(l10n.retry),
              ),
            ),
            loading: () => const LinearProgressIndicator(),
          ),
        ],
      ),
    );
  }
}
