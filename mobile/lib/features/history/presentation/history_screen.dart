import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/charts.dart';
import '../../../shared/widgets.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/answer_card.dart';
import '../data/history_repository.dart';
import '../domain/history_models.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(historyProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tabHistory),
          actions: [
            IconButton(
              tooltip: l10n.retry,
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(historyProvider),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: l10n.timelineTab),
            Tab(text: l10n.analyticsTab),
          ]),
        ),
        body: data.when(
          data: (d) => TabBarView(children: [
            _Timeline(data: d),
            _Analytics(data: d),
          ]),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(apiErrorMessage(l10n, e),
                  onRetry: () => ref.invalidate(historyProvider)),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

String _date(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatMediumDate(d.toLocal());

class _Timeline extends StatefulWidget {
  const _Timeline({required this.data});
  final HistoryData data;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  HistoryFilter _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = timeline(widget.data, _filter);
    final labels = {
      HistoryFilter.all: l10n.filterAll,
      HistoryFilter.symptoms: l10n.filterSymptoms,
      HistoryFilter.medicines: l10n.filterMedicines,
      HistoryFilter.reports: l10n.filterReports,
    };
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          for (final f in HistoryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels[f]!),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? EmptyState(l10n.historyEmpty, icon: Icons.history)
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, i) => _tile(context, l10n, items[i]),
              ),
      ),
    ]);
  }

  Widget _tile(BuildContext context, AppLocalizations l10n, TimelineItem item) {
    final (icon, color, title, subtitle) = switch (item) {
      SymptomItem(:final episode) => (
          Icons.healing,
          urgencyColor(Urgency.fromWire(episode.urgency)),
          episode.symptoms.isEmpty ? l10n.symptomCheck : episode.symptoms.join(', '),
          episode.urgency == null
              ? l10n.symptomCheck
              : '${l10n.symptomCheck} · ${urgencyLabel(l10n, Urgency.fromWire(episode.urgency))}',
        ),
      MedicineItem(:final lookup) => (
          Icons.medication,
          AppColors.teal,
          lookup.brand?.isNotEmpty == true ? lookup.brand! : lookup.query,
          l10n.medicineLookup,
        ),
      ReportTimelineItem(:final report) => (
          Icons.description,
          AppColors.navy,
          report.lab?.isNotEmpty == true ? report.lab! : l10n.labReport,
          report.confirmed
              ? l10n.labReport
              : '${l10n.labReport} · ${l10n.reportDraft}',
        ),
    };
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        trailing: Text(_date(context, item.date),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _Analytics extends StatefulWidget {
  const _Analytics({required this.data});
  final HistoryData data;

  @override
  State<_Analytics> createState() => _AnalyticsState();
}

class _AnalyticsState extends State<_Analytics> {
  String? _test;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = widget.data;
    if (d.episodes.isEmpty && d.values.isEmpty) {
      return EmptyState(l10n.analyticsEmpty, icon: Icons.insights);
    }
    final weekly = episodesPerWeek(d.episodes, DateTime.now());
    final top = topSymptoms(d.episodes);
    final avg = averageFollowups(d.episodes);
    final repeats = repeatCount(d.episodes);
    final tests = d.values.keys.toList()..sort();
    final test = (_test != null && tests.contains(_test)) ? _test! : tests.firstOrNull;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (repeats > 0)
        Card(
          color: AppColors.peach,
          child: ListTile(
            leading: const Icon(Icons.repeat, color: Color(0xFFE67E22)),
            title: Text(l10n.repeatBanner),
          ),
        ),
      if (d.episodes.isNotEmpty) ...[
        SectionTitle(l10n.episodesPerWeek),
        LabelledBarChart(bars: [
          for (final w in weekly) (label: shortDate(w.weekStart), value: w.count.toDouble()),
        ]),
        if (top.isNotEmpty) ...[
          SectionTitle(l10n.topSymptoms),
          LabelledBarChart(bars: [
            for (final s in top) (label: s.name, value: s.count.toDouble()),
          ]),
        ],
        if (avg != null)
          Card(
            color: Colors.white,
            margin: const EdgeInsets.only(top: 16),
            child: ListTile(
              title: Text(l10n.avgFollowups),
              trailing: Text(avg.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.navy)),
            ),
          ),
      ],
      SectionTitle(l10n.reportTrends),
      if (test == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(l10n.noReportValues,
              style: const TextStyle(color: AppColors.textSecondary)),
        )
      else ...[
        DropdownButtonFormField<String>(
          initialValue: test,
          decoration: InputDecoration(labelText: l10n.testName, isDense: true),
          items: [for (final t in tests) DropdownMenuItem(value: t, child: Text(t))],
          onChanged: (t) => setState(() => _test = t),
        ),
        TrendLineChart(
            points: [for (final p in d.values[test]!) (date: p.date, value: p.value)]),
      ],
    ]);
  }
}
