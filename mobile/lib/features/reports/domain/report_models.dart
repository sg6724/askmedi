import '../../../shared/source.dart';

enum ValueStatus { low, normal, high, unknown, unreadable }

ValueStatus statusFromWire(String? w) =>
    ValueStatus.values.where((s) => s.name == w).firstOrNull ?? ValueStatus.unknown;

class ReportValue {
  const ReportValue({
    required this.testName,
    this.value,
    this.unit,
    this.refLow,
    this.refHigh,
    this.refText,
    this.status = ValueStatus.unknown,
  });

  factory ReportValue.fromJson(Map<String, dynamic> j) => ReportValue(
        testName: (j['test_name'] as String?) ?? '',
        value: (j['value'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        refLow: (j['ref_low'] as num?)?.toDouble(),
        refHigh: (j['ref_high'] as num?)?.toDouble(),
        refText: j['ref_text'] as String?,
        status: statusFromWire(j['status'] as String?),
      );

  final String testName;
  final double? value;
  final String? unit;
  final double? refLow;
  final double? refHigh;
  final String? refText;
  final ValueStatus status;

  Map<String, dynamic> toJson() => {
        'test_name': testName,
        'value': value,
        'unit': unit,
        'ref_low': refLow,
        'ref_high': refHigh,
        'ref_text': refText,
        'status': status.name,
      };

  static List<ReportValue> listFrom(Object? json) => [
        for (final v in (json as List?) ?? const [])
          ReportValue.fromJson(Map<String, dynamic>.from(v as Map)),
      ];
}

/// Reads a printed range such as "12.0-15.5", "< 200" or "> 40".
({double? low, double? high}) parseRange(String text) {
  final t = text.replaceAll(',', '').trim();
  final between = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)').firstMatch(t);
  if (between != null) {
    return (low: double.parse(between[1]!), high: double.parse(between[2]!));
  }
  final below = RegExp(r'^(?:<|≤|<=|upto|up to)\s*(\d+(?:\.\d+)?)', caseSensitive: false)
      .firstMatch(t);
  if (below != null) return (low: null, high: double.parse(below[1]!));
  final above =
      RegExp(r'^(?:>|≥|>=)\s*(\d+(?:\.\d+)?)').firstMatch(t);
  if (above != null) return (low: double.parse(above[1]!), high: null);
  return (low: null, high: null);
}

class ParsedReport {
  const ParsedReport({
    required this.reportId,
    this.reportDate,
    this.lab,
    this.values = const [],
  });

  factory ParsedReport.fromJson(Map<String, dynamic> j) => ParsedReport(
        reportId: j['report_id'] as String,
        reportDate: j['report_date'] as String?,
        lab: j['lab'] as String?,
        values: ReportValue.listFrom(j['values']),
      );

  final String reportId;
  final String? reportDate;
  final String? lab;
  final List<ReportValue> values;
}

class ReportSummary {
  const ReportSummary({
    required this.reportId,
    this.summary = '',
    this.highlights = const [],
    this.values = const [],
    this.sources = const [],
    this.disclaimer = '',
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        reportId: (j['report_id'] as String?) ?? '',
        summary: (j['summary'] as String?) ?? '',
        highlights: stringList(j['highlights']),
        values: ReportValue.listFrom(j['values']),
        sources: Source.listFrom(j['sources']),
        disclaimer: (j['disclaimer'] as String?) ?? '',
      );

  final String reportId;
  final String summary;
  final List<String> highlights;
  final List<ReportValue> values;
  final List<Source> sources;
  final String disclaimer;
}

/// One stored value of a test, for trend charts.
class TestPoint {
  const TestPoint({required this.date, required this.value});
  final DateTime date;
  final double value;
}
