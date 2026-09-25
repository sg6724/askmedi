import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'consent_purpose.dart';
import 'consent_repository.dart';

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  final Map<ConsentPurpose, bool> _choices = {
    for (final p in ConsentPurpose.values) p: false,
  };
  bool _busy = false;
  String? _error;

  bool get _canContinue =>
      ConsentPurpose.values.where((p) => p.required).every((p) => _choices[p]!);

  String _label(AppLocalizations l10n, ConsentPurpose p) => switch (p) {
    ConsentPurpose.age18Plus => l10n.consentAge,
    ConsentPurpose.terms => l10n.consentTerms,
    ConsentPurpose.history => l10n.consentHistory,
    ConsentPurpose.media => l10n.consentMedia,
    ConsentPurpose.voice => l10n.consentVoice,
    ConsentPurpose.location => l10n.consentLocation,
  };

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(consentRepositoryProvider).save(Map.of(_choices));
      widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).genericError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(AppLocalizations l10n, ConsentPurpose p) => CheckboxListTile(
    value: _choices[p],
    onChanged: (v) => setState(() => _choices[p] = v ?? false),
    title: Text(_label(l10n, p)),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.consentTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            l10n.consentIntro,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.peach,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(l10n.consentAiNotice),
          ),
          const SizedBox(height: 16),
          for (final p in ConsentPurpose.values.where((p) => p.required))
            _tile(l10n, p),
          const Divider(height: 32),
          Text(
            l10n.consentOptionalNote,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          for (final p in ConsentPurpose.values.where((p) => !p.required))
            _tile(l10n, p),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canContinue && !_busy ? _save : null,
            child: Text(l10n.agreeAndContinue),
          ),
        ],
      ),
    );
  }
}
