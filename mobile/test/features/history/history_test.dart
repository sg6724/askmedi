import 'package:askmedi/features/history/data/history_repository.dart';
import 'package:askmedi/features/history/domain/history_models.dart';
import 'package:askmedi/features/history/presentation/history_screen.dart';
import 'package:askmedi/features/reports/domain/report_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakeHistory implements HistoryRepository {
  FakeHistory(this.data, {this.error});
  final HistoryData data;
  final Exception? error;

  @override
  Future<HistoryData> load() async {
    if (error != null) throw error!;
    return data;
  }
}

SymptomEpisode ep(
  String id,
  DateTime at,
  List<String> symptoms, {
  int followups = 0,
  bool repeat = false,
  String? urgency,
}) => SymptomEpisode(
  id: id,
  startedAt: at,
  symptoms: symptoms,
  followupCount: followups,
  repeatFlag: repeat,
  urgency: urgency,
);

void main() {
  final now = DateTime(2026, 9, 25, 12); // a Friday
  final data = HistoryData(
    episodes: [
      ep(
        'e1',
        now.subtract(const Duration(days: 1)),
        ['Fever', 'Headache'],
        followups: 3,
        urgency: 'see_doctor_soon',
      ),
      ep(
        'e2',
        now.subtract(const Duration(days: 2)),
        ['fever'],
        followups: 1,
        repeat: true,
      ),
      ep('e3', now.subtract(const Duration(days: 9)), ['Cough'], followups: 2),
    ],
    medicines: [
      MedicineLookupItem(
        id: 'm1',
        createdAt: now.subtract(const Duration(hours: 3)),
        query: 'Paracetamol',
        brand: 'Crocin 500',
      ),
    ],
    reports: [
      ReportItem(
        id: 'r1',
        createdAt: now.subtract(const Duration(days: 5)),
        lab: 'City Lab',
        confirmed: true,
      ),
    ],
    values: {
      'Haemoglobin': [
        TestPoint(date: DateTime(2026, 6, 1), value: 12.5),
        TestPoint(date: DateTime(2026, 9, 1), value: 11.2),
      ],
    },
  );

  group('analytics', () {
    test('episodes per week, oldest first, current week last', () {
      final weeks = episodesPerWeek(data.episodes, now, weeks: 3);
      expect(weeks.map((w) => w.count), [0, 1, 2]);
      expect(weeks.last.weekStart, DateTime(2026, 9, 21)); // Monday
    });

    test('top symptoms are case-insensitive and sorted by count', () {
      final top = topSymptoms(data.episodes);
      expect(top.first, (name: 'Fever', count: 2));
      expect(top.map((t) => t.name), containsAll(['Headache', 'Cough']));
    });

    test('average follow-ups and repeat count', () {
      expect(averageFollowups(data.episodes), 2.0);
      expect(averageFollowups(const []), isNull);
      expect(repeatCount(data.episodes), 1);
    });

    test('timeline is newest first and filters by kind', () {
      final all = timeline(data, HistoryFilter.all);
      expect(all.first, isA<MedicineItem>());
      expect(all, hasLength(5));
      expect(
        timeline(data, HistoryFilter.reports).single,
        isA<ReportTimelineItem>(),
      );
      expect(timeline(data, HistoryFilter.symptoms), hasLength(3));
    });
  });

  testWidgets(
    'timeline with filters, analytics with charts and repeat banner',
    (tester) async {
      await pumpRouted(
        tester,
        const HistoryScreen(),
        overrides: [
          historyRepositoryProvider.overrideWithValue(FakeHistory(data)),
        ],
      );

      expect(find.text('Crocin 500'), findsOneWidget);
      expect(find.text('City Lab'), findsOneWidget);
      expect(find.text('Fever, Headache'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Medicines'));
      await tester.pumpAndSettle();
      expect(find.text('Crocin 500'), findsOneWidget);
      expect(find.text('City Lab'), findsNothing);

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'You have asked about the same symptoms several times. Please see a doctor.',
        ),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsNWidgets(2));
      expect(find.text('2.0'), findsOneWidget);
      await tester.ensureVisible(find.byType(LineChart));
      expect(find.byType(LineChart), findsOneWidget);
    },
  );

  testWidgets('no data -> empty states, never fake data', (tester) async {
    await pumpRouted(
      tester,
      const HistoryScreen(),
      overrides: [
        historyRepositoryProvider.overrideWithValue(
          FakeHistory(const HistoryData()),
        ),
      ],
    );

    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(
      find.text('No data yet. Analytics appear after you use AskMedi.'),
      findsOneWidget,
    );
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets('load error -> message with Retry', (tester) async {
    await pumpRouted(
      tester,
      const HistoryScreen(),
      overrides: [
        historyRepositoryProvider.overrideWithValue(
          FakeHistory(const HistoryData(), error: Exception('offline')),
        ),
      ],
    );

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
