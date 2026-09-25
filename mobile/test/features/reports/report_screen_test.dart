import 'dart:typed_data';

import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/platform/file_pickers.dart';
import 'package:askmedi/features/reports/data/report_repository.dart';
import 'package:askmedi/features/reports/domain/report_models.dart';
import 'package:askmedi/features/reports/presentation/report_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakePickers implements FilePickers {
  @override
  Future<UploadFile?> pickPhoto(PhotoSource source) async => null;

  @override
  Future<UploadFile?> pickImageOrPdf() async => UploadFile(
    bytes: Uint8List.fromList([37, 80, 68, 70]),
    name: 'cbc.pdf',
    mimeType: 'application/pdf',
  );
}

class FakeReportRepository implements ReportRepository {
  FakeReportRepository({this.parseError});
  final Exception? parseError;
  List<ReportValue>? confirmed;
  String? confirmedId;

  @override
  Future<ParsedReport> parse(UploadFile file) async {
    if (parseError != null) throw parseError!;
    return ParsedReport.fromJson({
      'report_id': 'r-1',
      'report_date': '2026-09-01',
      'lab': 'City Lab',
      'values': [
        {
          'test_name': 'Haemoglobin',
          'value': 11.2,
          'unit': 'g/dL',
          'ref_low': 12,
          'ref_high': 15.5,
          'ref_text': '12.0-15.5',
          'status': 'low',
        },
      ],
    });
  }

  @override
  Future<ReportSummary> confirm(
    String reportId,
    List<ReportValue> values, {
    required String language,
  }) async {
    confirmedId = reportId;
    confirmed = values;
    return ReportSummary.fromJson({
      'report_id': reportId,
      'summary': 'Your haemoglobin is slightly low.',
      'highlights': ['Haemoglobin is below the printed range'],
      'values': [
        for (final v in values) {...v.toJson(), 'status': 'low'},
      ],
      'sources': [
        {
          'title': 'MedlinePlus: Hemoglobin test',
          'url': 'https://medlineplus.gov/hb',
        },
      ],
      'disclaimer': 'Not a diagnosis.',
    });
  }

  @override
  Future<List<TestPoint>> history(String testName) async => [
    TestPoint(date: DateTime(2026, 6, 1), value: 12.5),
    TestPoint(date: DateTime(2026, 9, 1), value: 11.0),
  ];
}

void main() {
  test('parseRange reads common printed ranges', () {
    expect(parseRange('12.0-15.5'), (low: 12.0, high: 15.5));
    expect(parseRange('4 to 11'), (low: 4.0, high: 11.0));
    expect(parseRange('< 200'), (low: null, high: 200.0));
    expect(parseRange('>40'), (low: 40.0, high: null));
    expect(parseRange('see note'), (low: null, high: null));
  });

  testWidgets(
    'pick -> edit extracted value -> confirm -> Summary / Key values / Chart',
    (tester) async {
      final repo = FakeReportRepository();
      await pumpRouted(
        tester,
        const ReportScreen(),
        overrides: [
          filePickersProvider.overrideWithValue(FakePickers()),
          reportRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await tester.tap(find.text('Choose image or PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Check the values'), findsOneWidget);
      expect(find.text('City Lab · 2026-09-01'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '11.2'), '11.0');
      await tester.tap(find.text('Confirm and explain'));
      await tester.pumpAndSettle();

      expect(repo.confirmedId, 'r-1');
      final v = repo.confirmed!.single;
      expect(v.testName, 'Haemoglobin');
      expect(v.value, 11.0);
      expect(v.refLow, 12);
      expect(v.refHigh, 15.5);

      expect(find.text('Your haemoglobin is slightly low.'), findsOneWidget);
      expect(find.text('MedlinePlus: Hemoglobin test'), findsOneWidget);

      await tester.tap(find.text('Key values'));
      await tester.pumpAndSettle();
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('11 g/dL'), findsOneWidget);

      await tester.tap(find.text('Chart'));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    },
  );

  testWidgets('file too large (413) shows an error and stays on the picker', (
    tester,
  ) async {
    await pumpRouted(
      tester,
      const ReportScreen(),
      overrides: [
        filePickersProvider.overrideWithValue(FakePickers()),
        reportRepositoryProvider.overrideWithValue(
          FakeReportRepository(
            parseError: const ApiException(
              statusCode: 413,
              code: 'file_too_large',
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text('Choose image or PDF'));
    await tester.pumpAndSettle();

    expect(find.text('This file is too large.'), findsOneWidget);
    expect(find.text('Choose image or PDF'), findsOneWidget);
  });
}
