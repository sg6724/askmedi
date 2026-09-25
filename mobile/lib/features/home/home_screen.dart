import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/routing/routes.dart';
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
    final actions = [
      (Icons.chat_bubble_outline, l10n.homeCheckSymptoms, l10n.homeCheckSymptomsSub,
          AppColors.sky, Routes.chat),
      (Icons.mic_none, l10n.homeTalk, l10n.homeTalkSub, AppColors.lavender, Routes.talk),
      (Icons.medication_outlined, l10n.homeScanMedicine, l10n.homeScanMedicineSub,
          AppColors.tealLight, Routes.medicine),
      (Icons.description_outlined, l10n.homeUploadReport, l10n.homeUploadReportSub,
          AppColors.peach, Routes.report),
      (Icons.local_hospital_outlined, l10n.homeFindHospital, l10n.homeFindHospitalSub,
          AppColors.blush, Routes.hospitals),
    ];
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
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size.fromHeight(60),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            onPressed: () => context.push(Routes.emergency),
            icon: const Icon(Icons.emergency),
            label: Text(l10n.emergencyButton),
          ),
          const SizedBox(height: 16),
          for (final (icon, title, subtitle, color, route) in actions)
            Card(
              color: color,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child: Icon(icon, color: AppColors.navy),
                ),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                // Hospitals is a tab: switch to it rather than stacking a page.
                onTap: () => route == Routes.hospitals
                    ? context.go(route)
                    : context.push(route),
              ),
            ),
          const SizedBox(height: 8),
          me.when(
            data: (_) => Row(children: [
              const Icon(Icons.cloud_done, size: 16, color: AppColors.teal),
              const SizedBox(width: 6),
              Text(l10n.serverConnected,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
            error: (_, _) => Row(children: [
              const Icon(Icons.cloud_off, size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l10n.serverUnreachable,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ),
              TextButton(
                onPressed: () => ref.invalidate(meProvider),
                child: Text(l10n.retry),
              ),
            ]),
            loading: () => const LinearProgressIndicator(minHeight: 2),
          ),
        ],
      ),
    );
  }
}
