import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../auth/auth_repository.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProfile)),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.signOut),
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ]),
    );
  }
}
