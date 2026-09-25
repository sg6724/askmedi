import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/report_models.dart';

abstract interface class ReportRepository {
  /// `POST /reports/parse`: extracts values; saved as a draft report.
  Future<ParsedReport> parse(UploadFile file);

  /// `POST /reports/{id}/confirm` with the user-checked values.
  Future<ReportSummary> confirm(
    String reportId,
    List<ReportValue> values, {
    required String language,
  });

  /// Every stored numeric value of [testName], oldest first (from Supabase).
  Future<List<TestPoint>> history(String testName);
}

class ApiReportRepository implements ReportRepository {
  ApiReportRepository(this._api, this._db);
  final ApiClient _api;
  final SupabaseClient _db;

  @override
  Future<ParsedReport> parse(UploadFile file) async => ParsedReport.fromJson(
    await _api.postFile('/reports/parse', 'file', file),
  );

  @override
  Future<ReportSummary> confirm(
    String reportId,
    List<ReportValue> values, {
    required String language,
  }) async => ReportSummary.fromJson(
    await _api.postJson('/reports/$reportId/confirm', {
      'values': [for (final v in values) v.toJson()],
      'language': language,
    }),
  );

  @override
  Future<List<TestPoint>> history(String testName) async {
    final rows = await _db
        .from('report_values')
        .select('value, report_date, created_at')
        .eq('test_name', testName)
        .order('created_at')
        .limit(200);
    return pointsFromRows(rows);
  }
}

/// Rows of `report_values` -> points, dated by the report date when known.
List<TestPoint> pointsFromRows(List<Map<String, dynamic>> rows) {
  final points = <TestPoint>[
    for (final r in rows)
      if (r['value'] != null)
        TestPoint(
          date: DateTime.parse((r['report_date'] ?? r['created_at']) as String),
          value: (r['value'] as num).toDouble(),
        ),
  ];
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ApiReportRepository(
    ref.watch(apiClientProvider),
    ref.watch(supabaseClientProvider),
  ),
);

/// autoDispose: per-user data, dropped when the screen closes.
final testHistoryProvider = FutureProvider.autoDispose
    .family<List<TestPoint>, String>(
      (ref, testName) => ref.watch(reportRepositoryProvider).history(testName),
      retry: (_, _) => null,
    );
