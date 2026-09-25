import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/report_models.dart';
import '../domain/history_models.dart';

abstract interface class HistoryRepository {
  Future<HistoryData> load();
}

/// Reads the user's own rows directly (RLS, user's JWT); no backend endpoint.
class SupabaseHistoryRepository implements HistoryRepository {
  SupabaseHistoryRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<HistoryData> load() async {
    final results = await Future.wait([
      _db
          .from('episodes')
          .select('id, started_at, symptoms, urgency, followup_count, repeat_flag')
          .eq('kind', 'symptom')
          .order('started_at', ascending: false)
          .limit(200),
      _db
          .from('medicine_lookups')
          .select('id, created_at, query, brand')
          .order('created_at', ascending: false)
          .limit(100),
      _db
          .from('reports')
          .select('id, created_at, report_date, lab, status')
          .order('created_at', ascending: false)
          .limit(100),
      _db
          .from('report_values')
          .select('test_name, value, report_date, created_at')
          .order('created_at')
          .limit(1000),
    ]);

    final byTest = <String, List<Map<String, dynamic>>>{};
    for (final r in results[3]) {
      if (r['value'] == null) continue;
      byTest.putIfAbsent(r['test_name'] as String, () => []).add(r);
    }

    return HistoryData(
      episodes: [for (final r in results[0]) SymptomEpisode.fromRow(r)],
      medicines: [for (final r in results[1]) MedicineLookupItem.fromRow(r)],
      reports: [for (final r in results[2]) ReportItem.fromRow(r)],
      values: <String, List<TestPoint>>{
        for (final e in byTest.entries) e.key: pointsFromRows(e.value),
      },
    );
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>(
    (ref) => SupabaseHistoryRepository(ref.watch(supabaseClientProvider)));

/// autoDispose: per-user data, dropped with the tab on sign-out.
final historyProvider = FutureProvider.autoDispose<HistoryData>(
  (ref) => ref.watch(historyRepositoryProvider).load(),
  retry: (_, _) => null,
);
