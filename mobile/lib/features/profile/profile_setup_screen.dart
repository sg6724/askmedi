import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../onboarding/locale_controller.dart';
import 'health_profile.dart';
import 'profile_repository.dart';
import 'profile_validators.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _birthYear = TextEditingController();
  Sex? _sex;
  bool? _pregnant;
  final _conditions = <String>[];
  final _medicines = <String>[];
  final _allergies = <String>[];
  String? _birthYearError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  String _sexLabel(AppLocalizations l10n, Sex s) => switch (s) {
        Sex.female => l10n.sexFemale,
        Sex.male => l10n.sexMale,
        Sex.other => l10n.sexOther,
        Sex.preferNot => l10n.sexPreferNot,
      };

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final err = validateBirthYear(_birthYear.text, DateTime.now());
    setState(() {
      _birthYearError = switch (err) {
        BirthYearError.invalid => l10n.birthYearInvalid,
        BirthYearError.under18 => l10n.birthYearUnder18,
        null => null,
      };
    });
    if (err != null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      await ref.read(profileRepositoryProvider).saveOnboardingProfile(
            HealthProfile(
              displayName: name.isEmpty ? null : name,
              birthYear: int.parse(_birthYear.text.trim()),
              sex: _sex,
              pregnant: _pregnant,
              conditions: List.of(_conditions),
              medicines: List.of(_medicines),
              allergies: List.of(_allergies),
            ),
            language: ref.read(localeControllerProvider)?.languageCode ?? 'en',
          );
      widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = l10n.genericError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.profileIntro,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.nameLabel)),
          const SizedBox(height: 12),
          TextField(
            controller: _birthYear,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
                labelText: l10n.birthYearLabel, errorText: _birthYearError),
          ),
          Text(l10n.sexLabel),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Sex.values)
                ChoiceChip(
                  label: Text(_sexLabel(l10n, s)),
                  selected: _sex == s,
                  onSelected: (_) => setState(() {
                    _sex = s;
                    if (s != Sex.female) _pregnant = null;
                  }),
                ),
            ],
          ),
          if (_sex == Sex.female) ...[
            const SizedBox(height: 12),
            Text(l10n.pregnantLabel),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: Text(l10n.yes),
                  selected: _pregnant == true,
                  onSelected: (_) => setState(() => _pregnant = true)),
              ChoiceChip(
                  label: Text(l10n.no),
                  selected: _pregnant == false,
                  onSelected: (_) => setState(() => _pregnant = false)),
            ]),
          ],
          const SizedBox(height: 16),
          _ChipListField(label: l10n.conditionsLabel, hint: l10n.addItemHint, items: _conditions),
          _ChipListField(label: l10n.medicinesLabel, hint: l10n.addItemHint, items: _medicines),
          _ChipListField(label: l10n.allergiesLabel, hint: l10n.addItemHint, items: _allergies),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.saveAndContinue),
          ),
        ],
      ),
    );
  }
}

/// Free-text list: type, press Enter to add a chip, tap a chip's x to remove it.
class _ChipListField extends StatefulWidget {
  const _ChipListField({required this.label, required this.hint, required this.items});

  final String label;
  final String hint;
  final List<String> items;

  @override
  State<_ChipListField> createState() => _ChipListFieldState();
}

class _ChipListFieldState extends State<_ChipListField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String value) {
    final v = value.trim();
    if (v.isEmpty || v.length > 120 || widget.items.contains(v)) return;
    setState(() => widget.items.add(v));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: _add,
            decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final item in widget.items)
                InputChip(
                  label: Text(item),
                  onDeleted: () => setState(() => widget.items.remove(item)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
