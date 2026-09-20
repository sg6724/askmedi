import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), label: l10n.tabHome),
          NavigationDestination(icon: const Icon(Icons.history), label: l10n.tabHistory),
          NavigationDestination(
              icon: const Icon(Icons.local_hospital_outlined), label: l10n.tabHospitals),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: l10n.tabProfile),
        ],
      ),
    );
  }
}
