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
  // Owned here, not by ChipListField: the form is a lazy ListView, so a field
  // scrolled far off screen is disposed and would take its typed text with it.
  final _conditionsInput = TextEditingController();
  final _medicinesInput = TextEditingController();
  final _allergiesInput = TextEditingController();
  String? _birthYearError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    _conditionsInput.dispose();
    _medicinesInput.dispose();
    _allergiesInput.dispose();
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
    // Text typed but not yet added (no Enter / + tap) must not be silently
    // dropped: commit it before validating and saving.
    commitChipText(_conditions, _conditionsInput);
    commitChipText(_medicines, _medicinesInput);
    commitChipText(_allergies, _allergiesInput);
    final err = validateBirthYear(_birthYear.text, DateTime.now());
    setState(() {
      // Rebuilds the chip lists (mutated above) as well as the year error.
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
          ChipListField(
              label: l10n.conditionsLabel,
              hint: l10n.addItemHint,
              controller: _conditionsInput,
              items: _conditions),
          ChipListField(
              label: l10n.medicinesLabel,
              hint: l10n.addItemHint,
              controller: _medicinesInput,
              items: _medicines),
          ChipListField(
              label: l10n.allergiesLabel,
              hint: l10n.addItemHint,
              controller: _allergiesInput,
              items: _allergies),
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

/// Adds the text in [controller] to [items] and clears the controller. The one
/// place that defines what a valid chip is: trimmed, non-empty, at most 120
/// characters, no duplicates. Returns whether an item was added (invalid text is
/// left in the field). Used by the field's Enter / + action and by the screen's
/// save, which commits text that was typed but never added.
bool commitChipText(List<String> items, TextEditingController controller) {
  final v = controller.text.trim();
  if (v.isEmpty || v.length > 120 || items.contains(v)) return false;
  items.add(v);
  controller.clear();
  return true;
}

/// Free-text list: type, then press Enter or tap + to add a chip; tap a chip's
/// x to remove it. The text controller is owned by the parent so uncommitted
/// text outlives this widget being scrolled out of a lazy list.
class ChipListField extends StatefulWidget {
  const ChipListField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.items,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final List<String> items;

  @override
  State<ChipListField> createState() => _ChipListFieldState();
}

class _ChipListFieldState extends State<ChipListField> {
  void _add() {
    if (commitChipText(widget.items, widget.controller)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: l10n.addItem,
                onPressed: _add,
              ),
            ),
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
