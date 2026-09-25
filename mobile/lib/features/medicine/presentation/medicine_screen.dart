import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/platform/file_pickers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets.dart';
import '../../onboarding/locale_controller.dart';
import '../data/medicine_repository.dart';
import '../domain/medicine_models.dart';

enum _Step { pick, busy, confirm, result }

/// Photo -> scan -> "Is this X?" -> lookup -> uses, warnings, pharmacist flags.
class MedicineScreen extends ConsumerStatefulWidget {
  const MedicineScreen({super.key});

  @override
  ConsumerState<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends ConsumerState<MedicineScreen> {
  final _name = TextEditingController();
  _Step _step = _Step.pick;
  String? _busyText;
  String? _error;
  bool _typing = false;
  List<MedicineCandidate> _candidates = const [];
  MedicineInfo? _info;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _scan(PhotoSource source) async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(filePickersProvider).pickPhoto(source);
    if (file == null || !mounted) return;
    setState(() {
      _step = _Step.busy;
      _busyText = l10n.scanning;
      _error = null;
    });
    try {
      final candidates = await ref.read(medicineRepositoryProvider).scan(file);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        if (candidates.isEmpty) {
          _step = _Step.pick;
          _typing = true;
          _error = l10n.unreadableImage;
        } else {
          _step = _Step.confirm;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.pick;
        _typing = true; // typing the name always works as a fallback
        _error = apiErrorMessage(l10n, e);
      });
    }
  }

  Future<void> _lookup(String name, {String? brand}) async {
    final l10n = AppLocalizations.of(context);
    if (name.trim().isEmpty) return;
    final previous = _step;
    setState(() {
      _step = _Step.busy;
      _busyText = l10n.loadingInfo;
      _error = null;
    });
    try {
      final info = await ref.read(medicineRepositoryProvider).lookup(
            name: name.trim(),
            brand: brand,
            language: ref.read(appLanguageProvider),
          );
      if (!mounted) return;
      setState(() {
        _info = info;
        _step = _Step.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = previous;
        _error = apiErrorMessage(l10n, e);
      });
    }
  }

  void _restart() => setState(() {
        _step = _Step.pick;
        _typing = false;
        _error = null;
        _info = null;
        _candidates = const [];
        _name.clear();
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.medicineTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ErrorBanner(_error!),
          ...switch (_step) {
            _Step.pick => _pick(l10n),
            _Step.busy => [
                const SizedBox(height: 48),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Center(child: Text(_busyText ?? '')),
              ],
            _Step.confirm => _confirm(l10n),
            _Step.result => _result(l10n, _info!),
          },
        ],
      ),
    );
  }

  List<Widget> _pick(AppLocalizations l10n) => [
        Text(l10n.medicineIntro),
        const SizedBox(height: 20),
        // On the web the camera option also opens a file chooser.
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () => _scan(PhotoSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: Text(l10n.takePhoto),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => _scan(PhotoSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: Text(l10n.choosePhoto),
        ),
        const SizedBox(height: 12),
        if (!_typing)
          TextButton(
            onPressed: () => setState(() => _typing = true),
            child: Text(l10n.typeNameInstead),
          )
        else
          _typeName(l10n),
      ];

  Widget _typeName(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(children: [
          TextField(
            controller: _name,
            maxLength: 200,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => _lookup(v),
            decoration: InputDecoration(labelText: l10n.medicineNameLabel),
          ),
          FilledButton(
            onPressed: () => _lookup(_name.text),
            child: Text(l10n.lookUp),
          ),
        ]),
      );

  List<Widget> _confirm(AppLocalizations l10n) {
    final best = _candidates.first;
    final others = _candidates.skip(1).toList();
    return [
      Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.isThisMedicine(best.brand, best.saltsText),
                style: Theme.of(context).textTheme.titleMedium),
            if (best.manufacturer != null)
              Text(best.manufacturer!,
                  style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _lookup(best.lookupName, brand: best.brand),
              child: Text(l10n.yesThatsIt),
            ),
          ]),
        ),
      ),
      if (others.isNotEmpty) ...[
        SectionTitle(l10n.otherMatches),
        for (final c in others)
          Card(
            child: ListTile(
              title: Text(c.brand),
              subtitle: Text(c.saltsText),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _lookup(c.lookupName, brand: c.brand),
            ),
          ),
      ],
      const SizedBox(height: 8),
      if (!_typing)
        TextButton(
          onPressed: () => setState(() => _typing = true),
          child: Text(l10n.typeNameInstead),
        )
      else
        _typeName(l10n),
    ];
  }

  List<Widget> _result(AppLocalizations l10n, MedicineInfo info) => [
        Text(info.brand?.isNotEmpty == true ? info.brand! : info.name,
            style: Theme.of(context).textTheme.headlineSmall),
        if (info.salts.isNotEmpty)
          Text(info.salts.join(', '),
              style: const TextStyle(color: AppColors.textSecondary))
        else if (info.brand?.isNotEmpty == true)
          Text(info.name, style: const TextStyle(color: AppColors.textSecondary)),
        if (info.pharmacistFlags.isNotEmpty)
          Card(
            color: AppColors.peach,
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFE67E22)),
                  const SizedBox(width: 8),
                  Text(l10n.pharmacistFlagsTitle,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                BulletList(info.pharmacistFlags),
              ]),
            ),
          ),
        if (info.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(info.summary),
          ),
        if (info.uses.isNotEmpty) ...[SectionTitle(l10n.uses), BulletList(info.uses)],
        if (info.warnings.isNotEmpty) ...[
          SectionTitle(l10n.warnings),
          BulletList(info.warnings),
        ],
        SourcesList(info.sources),
        DisclaimerText(info.disclaimer),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _restart,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.scanAnother),
        ),
      ];
}
