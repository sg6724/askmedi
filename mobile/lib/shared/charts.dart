import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// A line of dated values (x = position, labelled with the date).
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({super.key, required this.points, this.height = 220});

  final List<({DateTime date, double value})> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, top: 12),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).clamp(1, 1000).toDouble(),
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i != value || i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(shortDate(points[i].date),
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (final (i, p) in points.indexed) FlSpot(i.toDouble(), p.value),
                ],
                color: AppColors.teal,
                barWidth: 3,
                dotData: const FlDotData(show: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical bars with a text label under each.
class LabelledBarChart extends StatelessWidget {
  const LabelledBarChart({super.key, required this.bars, this.height = 200});

  final List<({String label, double value})> bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) => value == value.roundToDouble()
                      ? SideTitleWidget(
                          meta: meta,
                          child: Text(value.toInt().toString(),
                              style: const TextStyle(fontSize: 10)))
                      : const SizedBox.shrink(),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                    final label = bars[i].label;
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        label.length > 10 ? '${label.substring(0, 9)}…' : label,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (final (i, b) in bars.indexed)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: b.value,
                    color: AppColors.navy,
                    width: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
