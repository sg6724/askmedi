import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'locale_controller.dart';

class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  static const _options = [
    (Locale('en'), 'English', 'Hello!'),
    (Locale('hi'), 'हिंदी', 'नमस्ते!'),
    (Locale('mr'), 'मराठी', 'नमस्कार!'),
  ];

  Locale _selected = const Locale('en');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The options scroll so the Continue button stays reachable at
              // large text scales and on short screens.
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      l10n.chooseLanguage,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.languageHint,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    for (final (locale, name, sample) in _options)
                      Card(
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text(sample),
                          trailing: _selected == locale
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.navy,
                                )
                              : null,
                          onTap: () => setState(() => _selected = locale),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref
                    .read(localeControllerProvider.notifier)
                    .setLocale(_selected),
                child: Text(l10n.continueButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
