import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'admin_palette.dart';

enum ChartPeriod { week, month, year }

extension ChartPeriodLabel on ChartPeriod {
  String get label => switch (this) {
        ChartPeriod.week => 'This Week',
        ChartPeriod.month => 'This Month',
        ChartPeriod.year => 'This Year',
      };
}

/// Created / In Progress / Completed job counts bucketed by day (week),
/// by week-of-month (month), or by month (year) — all from real
/// createdAt/startedAt/completedAt timestamps already on JobModel.
class JobsOverviewChart extends StatelessWidget {
  final AdminPalette palette;
  final List<String> xLabels;
  final List<double> created;
  final List<double> inProgress;
  final List<double> completed;
  final List<String> seriesNames;

  const JobsOverviewChart({
    super.key,
    required this.palette,
    required this.xLabels,
    required this.created,
    required this.inProgress,
    required this.completed,
    this.seriesNames = const ['Created', 'In Progress', 'Completed'],
  });

  @override
  Widget build(BuildContext context) {
    final maxY = [...created, ...inProgress, ...completed]
            .fold<double>(0, (m, v) => v > m ? v : m) *
        1.25;
    final safeMaxY = maxY <= 0 ? 10.0 : maxY;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: safeMaxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: safeMaxY / 5,
            getDrawingHorizontalLine: (_) => FlLine(
              color: palette.border,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: safeMaxY / 5,
                getTitlesWidget: (v, _) => Text(
                  v.round().toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: palette.textTertiary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= xLabels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      xLabels[i],
                      style: TextStyle(
                        fontSize: 10,
                        color: palette.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => palette.bg2,
              tooltipBorder: BorderSide(color: palette.border),
              getTooltipItems: (spots) => spots.map((s) {
                final names = seriesNames;
                final colors = [
                  AdminPalette.purple,
                  AdminPalette.blue,
                  AdminPalette.green
                ];
                return LineTooltipItem(
                  '${names[s.barIndex]}: ${s.y.round()}',
                  TextStyle(
                    color: colors[s.barIndex],
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    fontFamily: 'Inter',
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            _line(created, AdminPalette.purple),
            _line(inProgress, AdminPalette.blue),
            _line(completed, AdminPalette.green),
          ],
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> values, Color color) => LineChartBarData(
        spots: [
          for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
        ],
        isCurved: true,
        curveSmoothness: 0.3,
        color: color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
          ),
        ),
      );
}

class ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final AdminPalette palette;
  const ChartLegendDot({
    super.key,
    required this.color,
    required this.label,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: palette.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

/// Donut chart for Customers / Artisans / Admins composition.
class UsersDonutChart extends StatelessWidget {
  final AdminPalette palette;
  final int customers;
  final int artisans;
  final int admins;

  const UsersDonutChart({
    super.key,
    required this.palette,
    required this.customers,
    required this.artisans,
    required this.admins,
  });

  @override
  Widget build(BuildContext context) {
    final total = customers + artisans + admins;
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 64,
              sections: [
                PieChartSectionData(
                  value: customers.toDouble().clamp(0.0001, double.infinity),
                  color: AdminPalette.purple,
                  showTitle: false,
                  radius: 26,
                ),
                PieChartSectionData(
                  value: artisans.toDouble().clamp(0.0001, double.infinity),
                  color: AdminPalette.blue,
                  showTitle: false,
                  radius: 26,
                ),
                PieChartSectionData(
                  value: admins.toDouble().clamp(0.0001, double.infinity),
                  color: AdminPalette.amber,
                  showTitle: false,
                  radius: 26,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                'Total Users',
                style: TextStyle(
                  fontSize: 11.5,
                  color: palette.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Minimal sparkline used by Platform Health cards.
class AdminSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const AdminSparkline({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, (m, v) => v > m ? v : m);
    final safeMaxY = maxY <= 0 ? 1.0 : maxY;
    return SizedBox(
      height: 36,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: safeMaxY * 1.2,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
