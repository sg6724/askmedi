import '../../reports/domain/report_models.dart';

class SymptomEpisode {
  const SymptomEpisode({
    required this.id,
    required this.startedAt,
    this.symptoms = const [],
    this.urgency,
    this.followupCount = 0,
    this.repeatFlag = false,
  });

  factory SymptomEpisode.fromRow(Map<String, dynamic> r) => SymptomEpisode(
    id: r['id'] as String,
    startedAt: DateTime.parse(r['started_at'] as String),
    symptoms: [
      for (final s in (r['symptoms'] as List?) ?? const []) s.toString(),
    ],
    urgency: r['urgency'] as String?,
    followupCount: (r['followup_count'] as num?)?.toInt() ?? 0,
    repeatFlag: (r['repeat_flag'] as bool?) ?? false,
  );

  final String id;
  final DateTime startedAt;
  final List<String> symptoms;
  final String? urgency;
  final int followupCount;
  final bool repeatFlag;
}

class MedicineLookupItem {
  const MedicineLookupItem({
    required this.id,
    required this.createdAt,
    required this.query,
    this.brand,
  });

  factory MedicineLookupItem.fromRow(Map<String, dynamic> r) =>
      MedicineLookupItem(
        id: r['id'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        query: (r['query'] as String?) ?? '',
        brand: r['brand'] as String?,
      );

  final String id;
  final DateTime createdAt;
  final String query;
  final String? brand;
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.createdAt,
    this.reportDate,
    this.lab,
    this.confirmed = false,
  });

  factory ReportItem.fromRow(Map<String, dynamic> r) => ReportItem(
    id: r['id'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    reportDate: r['report_date'] == null
        ? null
        : DateTime.parse(r['report_date'] as String),
    lab: r['lab'] as String?,
    confirmed: r['status'] == 'confirmed',
  );

  final String id;
  final DateTime createdAt;
  final DateTime? reportDate;
  final String? lab;
  final bool confirmed;
}

/// Everything the History tab shows, read from Supabase under RLS.
class HistoryData {
  const HistoryData({
    this.episodes = const [],
    this.medicines = const [],
    this.reports = const [],
    this.values = const {},
  });

  final List<SymptomEpisode> episodes;
  final List<MedicineLookupItem> medicines;
  final List<ReportItem> reports;

  /// Numeric report values per test name, oldest first.
  final Map<String, List<TestPoint>> values;

  bool get isEmpty =>
      episodes.isEmpty &&
      medicines.isEmpty &&
      reports.isEmpty &&
      values.isEmpty;
}

enum HistoryFilter { all, symptoms, medicines, reports }

sealed class TimelineItem {
  const TimelineItem(this.date);
  final DateTime date;
}

class SymptomItem extends TimelineItem {
  SymptomItem(this.episode) : super(episode.startedAt);
  final SymptomEpisode episode;
}

class MedicineItem extends TimelineItem {
  MedicineItem(this.lookup) : super(lookup.createdAt);
  final MedicineLookupItem lookup;
}

class ReportTimelineItem extends TimelineItem {
  ReportTimelineItem(this.report) : super(report.createdAt);
  final ReportItem report;
}

/// Newest first, limited to [filter].
List<TimelineItem> timeline(HistoryData d, HistoryFilter filter) {
  final items = <TimelineItem>[
    if (filter == HistoryFilter.all || filter == HistoryFilter.symptoms)
      ...d.episodes.map(SymptomItem.new),
    if (filter == HistoryFilter.all || filter == HistoryFilter.medicines)
      ...d.medicines.map(MedicineItem.new),
    if (filter == HistoryFilter.all || filter == HistoryFilter.reports)
      ...d.reports.map(ReportTimelineItem.new),
  ];
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
}

// -- Analytics (pure, computed from the rows above) --------------------------

DateTime _weekStart(DateTime d) {
  final local = d.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// Symptom checks per week for the last [weeks] weeks (oldest first).
List<({DateTime weekStart, int count})> episodesPerWeek(
  List<SymptomEpisode> episodes,
  DateTime now, {
  int weeks = 8,
}) {
  final current = _weekStart(now);
  final starts = [
    for (var i = weeks - 1; i >= 0; i--)
      DateTime(current.year, current.month, current.day - 7 * i),
  ];
  final counts = {for (final s in starts) s: 0};
  for (final e in episodes) {
    final w = _weekStart(e.startedAt);
    if (counts.containsKey(w)) counts[w] = counts[w]! + 1;
  }
  return [for (final s in starts) (weekStart: s, count: counts[s]!)];
}

/// The most mentioned symptoms, case-insensitively, most frequent first.
List<({String name, int count})> topSymptoms(
  List<SymptomEpisode> episodes, {
  int limit = 5,
}) {
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final e in episodes) {
    for (final s in e.symptoms.toSet()) {
      final key = s.trim().toLowerCase();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => s.trim());
    }
  }
  final sorted = counts.entries.toList()
    ..sort(
      (a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key),
    );
  return [
    for (final e in sorted.take(limit)) (name: display[e.key]!, count: e.value),
  ];
}

/// Null when there are no symptom checks.
double? averageFollowups(List<SymptomEpisode> episodes) => episodes.isEmpty
    ? null
    : episodes.map((e) => e.followupCount).reduce((a, b) => a + b) /
          episodes.length;

int repeatCount(List<SymptomEpisode> episodes) =>
    episodes.where((e) => e.repeatFlag).length;
