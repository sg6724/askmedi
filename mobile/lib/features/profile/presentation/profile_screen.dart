import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/auth_repository.dart';
import '../../home/home_screen.dart';
import '../../onboarding/locale_controller.dart';
import '../data/account_repository.dart';
import '../health_profile.dart';
import '../profile_repository.dart';
import '../profile_setup_screen.dart';

const _languages = [
  (Locale('en'), 'English'),
  (Locale('hi'), 'हिंदी'),
  (Locale('mr'), 'मराठी'),
];

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _deleting = false;
  String? _error;

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAccountConfirmTitle),
        content: Text(l10n.deleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).deleteAccount();
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = l10n.genericError;
        });
      }
      return;
    }
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      // The user no longer exists; the local session is cleared regardless.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProfile)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l10n.editHealthProfile),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.editProfile),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.languageLabel),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (l, name) in _languages)
                  ChoiceChip(
                    label: Text(name),
                    selected: locale?.languageCode == l.languageCode,
                    onSelected: (_) => ref
                        .read(localeControllerProvider.notifier)
                        .setLocale(l),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.signOut),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
          ListTile(
            leading: _deleting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever, color: AppColors.danger),
            title: Text(
              l10n.deleteAccount,
              style: const TextStyle(color: AppColors.danger),
            ),
            onTap: _deleting ? null : _deleteAccount,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(_error!),
            ),
        ],
      ),
    );
  }
}

/// autoDispose: per-user data, fetched fresh each time the editor opens.
final storedProfileProvider = FutureProvider.autoDispose<HealthProfile?>(
  (ref) => ref.watch(profileRepositoryProvider).loadProfile(),
  retry: (_, _) => null,
);

/// Loads the stored profile, then shows the profile form in edit mode.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(storedProfileProvider)
        .when(
          data: (p) => ProfileSetupScreen(
            initial: p ?? const HealthProfile(birthYear: 0),
            onSaved: () {
              ref.invalidate(storedProfileProvider);
              ref.invalidate(displayNameProvider);
              if (context.canPop()) context.pop();
            },
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: Text(l10n.editHealthProfile)),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(
                l10n.genericError,
                onRetry: () => ref.invalidate(storedProfileProvider),
              ),
            ),
          ),
          loading: () => Scaffold(
            appBar: AppBar(title: Text(l10n.editHealthProfile)),
            body: const Center(child: CircularProgressIndicator()),
          ),
        );
  }
}
