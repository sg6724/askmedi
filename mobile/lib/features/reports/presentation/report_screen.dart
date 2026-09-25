import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/network/api_client.dart';
import '../../../core/platform/file_pickers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/charts.dart';
import '../../../shared/widgets.dart';
import '../../onboarding/locale_controller.dart';
import '../data/report_repository.dart';
import '../domain/report_models.dart';

Color statusColor(ValueStatus s) => switch (s) {
  ValueStatus.low => const Color(0xFF2E86DE),
  ValueStatus.normal => AppColors.teal,
  ValueStatus.high => AppColors.danger,
  ValueStatus.unknown || ValueStatus.unreadable => AppColors.textSecondary,
};

String statusLabel(AppLocalizations l10n, ValueStatus s) => switch (s) {
  ValueStatus.low => l10n.statusLow,
  ValueStatus.normal => l10n.statusNormal,
  ValueStatus.high => l10n.statusHigh,
  ValueStatus.unknown => l10n.statusUnknown,
  ValueStatus.unreadable => l10n.statusUnreadable,
};

/// Editable text for one extracted row.
class _Row {
  _Row(ReportValue v)
    : original = v,
      test = TextEditingController(text: v.testName),
      value = TextEditingController(text: _num(v.value)),
      unit = TextEditingController(text: v.unit ?? ''),
      range = TextEditingController(
        text:
            v.refText ??
            (v.refLow != null || v.refHigh != null
                ? '${_num(v.refLow)}-${_num(v.refHigh)}'
                : ''),
      );

  final ReportValue original;
  final TextEditingController test;
  final TextEditingController value;
  final TextEditingController unit;
  final TextEditingController range;

  static String _num(double? d) => d == null
      ? ''
      : (d == d.roundToDouble() ? d.toInt().toString() : d.toString());

  ReportValue toValue() {
    final rangeText = range.text.trim();
    final parsedRange = parseRange(rangeText);
    final rangeChanged = rangeText != (original.refText ?? '');
    final v = double.tryParse(value.text.trim().replaceAll(',', ''));
    return ReportValue(
      testName: test.text.trim(),
      value: v,
      unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
      refLow: rangeChanged
          ? parsedRange.low
          : original.refLow ?? parsedRange.low,
      refHigh: rangeChanged
          ? parsedRange.high
          : original.refHigh ?? parsedRange.high,
      refText: rangeText.isEmpty ? null : rangeText,
      // The server recomputes the status from the range.
      status: v == null ? ValueStatus.unreadable : original.status,
    );
  }

  void dispose() {
    test.dispose();
    value.dispose();
    unit.dispose();
    range.dispose();
  }
}

enum _Step { pick, busy, confirm, summary }

/// Pick file -> parse -> confirm table -> summary (Summary / Key values / Chart).
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  _Step _step = _Step.pick;
  String? _busyText;
  String? _error;
  ParsedReport? _parsed;
  final _rows = <_Row>[];
  ReportSummary? _summary;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(Future<UploadFile?> Function(FilePickers) picker) async {
    final l10n = AppLocalizations.of(context);
    final file = await picker(ref.read(filePickersProvider));
    if (file == null || !mounted) return;
    if (file.bytes.length > maxUploadBytes) {
      setState(() => _error = l10n.pdfTooLarge);
      return;
    }
    setState(() {
      _step = _Step.busy;
      _busyText = l10n.readingReport;
      _error = null;
    });
    try {
      final parsed = await ref.read(reportRepositoryProvider).parse(file);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..addAll(parsed.values.map(_Row.new));
        _step = _Step.confirm;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.pick;
        _error = apiErrorMessage(l10n, e);
      });
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    final values = [
      for (final r in _rows)
        if (r.test.text.trim().isNotEmpty) r.toValue(),
    ];
    setState(() {
      _step = _Step.busy;
      _busyText = l10n.thinking;
      _error = null;
    });
    try {
      final summary = await ref
          .read(reportRepositoryProvider)
          .confirm(
            _parsed!.reportId,
            values,
            language: ref.read(appLanguageProvider),
          );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _step = _Step.summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.confirm;
        _error = apiErrorMessage(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_step == _Step.summary) {
      return _SummaryView(summary: _summary!, onAgain: _restart);
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ErrorBanner(_error!),
          ...switch (_step) {
            _Step.pick => [
              Text(l10n.reportIntro),
              const SizedBox(height: 20),
              // On the web the camera option also opens a file chooser.
              if (!kIsWeb) ...[
                FilledButton.icon(
                  onPressed: () =>
                      _pick((p) => p.pickPhoto(PhotoSource.camera)),
                  icon: const Icon(Icons.photo_camera),
                  label: Text(l10n.takePhoto),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => _pick((p) => p.pickPhoto(PhotoSource.gallery)),
                icon: const Icon(Icons.photo_library),
                label: Text(l10n.choosePhoto),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => _pick((p) => p.pickPdf()),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(l10n.choosePdf),
              ),
            ],
            _Step.busy => [
              const SizedBox(height: 48),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Center(child: Text(_busyText ?? '')),
            ],
            _Step.confirm => _confirmTable(l10n),
            _Step.summary => const [],
          },
        ],
      ),
    );
  }

  void _restart() => setState(() {
    _step = _Step.pick;
    _summary = null;
    _parsed = null;
    _error = null;
  });

  List<Widget> _confirmTable(AppLocalizations l10n) => [
    Text(
      l10n.confirmValuesTitle,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    if (_parsed?.lab != null || _parsed?.reportDate != null)
      Text(
        [_parsed?.lab, _parsed?.reportDate].whereType<String>().join(' · '),
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    const SizedBox(height: 4),
    Text(l10n.confirmValuesIntro),
    const SizedBox(height: 12),
    if (_rows.isEmpty) Text(l10n.noValuesFound),
    for (final (i, r) in _rows.indexed)
      Card(
        key: ObjectKey(r),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r.test,
                      decoration: InputDecoration(
                        labelText: l10n.testName,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.removeRow,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _rows.removeAt(i).dispose()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r.value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.valueLabel,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: r.unit,
                      decoration: InputDecoration(
                        labelText: l10n.unitLabel,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: r.range,
                      decoration: InputDecoration(
                        labelText: l10n.rangeLabel,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    TextButton.icon(
      onPressed: () =>
          setState(() => _rows.add(_Row(const ReportValue(testName: '')))),
      icon: const Icon(Icons.add),
      label: Text(l10n.addRow),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: _rows.isEmpty ? null : _confirm,
      child: Text(l10n.confirmAndExplain),
    ),
  ];
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary, required this.onAgain});
  final ReportSummary summary;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.reportTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.tabSummary),
              Tab(text: l10n.tabKeyValues),
              Tab(text: l10n.tabChart),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(summary.summary),
                if (summary.highlights.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  BulletList(summary.highlights),
                ],
                SourcesList(summary.sources),
                DisclaimerText(summary.disclaimer),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onAgain,
                  icon: const Icon(Icons.upload_file),
                  label: Text(l10n.uploadAnother),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final v in summary.values) KeyValueTile(value: v),
                DisclaimerText(summary.disclaimer),
              ],
            ),
            _ChartTab(values: summary.values),
          ],
        ),
      ),
    );
  }
}

class KeyValueTile extends StatelessWidget {
  const KeyValueTile({super.key, required this.value});
  final ReportValue value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = statusColor(value.status);
    final v = value.value;
    return Card(
      color: Colors.white,
      child: ListTile(
        title: Text(
          value.testName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: value.refText == null || value.refText!.isEmpty
            ? null
            : Text('${l10n.rangeLabel}: ${value.refText}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              v == null ? '—' : '${_fmt(v)} ${value.unit ?? ''}'.trim(),
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel(l10n, value.status),
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

class _ChartTab extends ConsumerStatefulWidget {
  const _ChartTab({required this.values});
  final List<ReportValue> values;

  @override
  ConsumerState<_ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends ConsumerState<_ChartTab> {
  String? _test;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tests = {
      for (final v in widget.values)
        if (v.value != null && v.testName.isNotEmpty) v.testName,
    }.toList();
    if (tests.isEmpty) {
      return EmptyState(l10n.chartEmpty, icon: Icons.show_chart);
    }
    final test = (_test != null && tests.contains(_test))
        ? _test!
        : tests.first;
    final history = ref.watch(testHistoryProvider(test));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: test,
          decoration: InputDecoration(labelText: l10n.testName),
          items: [
            for (final t in tests) DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (t) => setState(() => _test = t),
        ),
        const SizedBox(height: 12),
        history.when(
          data: (points) => points.isEmpty
              ? EmptyState(l10n.chartEmpty, icon: Icons.show_chart)
              : TrendLineChart(
                  points: [
                    for (final p in points) (date: p.date, value: p.value),
                  ],
                ),
          error: (e, _) => ErrorBanner(
            apiErrorMessage(l10n, e),
            onRetry: () => ref.invalidate(testHistoryProvider(test)),
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ],
    );
  }
}
