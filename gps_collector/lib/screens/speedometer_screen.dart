import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import '../services/tracking_service.dart';

enum _ChartMode { line, bar }

enum _TimeWindow {
  all('All', null),
  last30s('30s', Duration(seconds: 30)),
  last1m('1m', Duration(minutes: 1)),
  last5m('5m', Duration(minutes: 5));

  final String label;
  final Duration? duration;
  const _TimeWindow(this.label, this.duration);
}

class SpeedometerScreen extends StatefulWidget {
  final TrackingService trackingService;

  const SpeedometerScreen({super.key, required this.trackingService});

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  _ChartMode _chartMode = _ChartMode.line;
  _TimeWindow _timeWindow = _TimeWindow.all;

  // Store the previous callback so we can restore it on dispose.
  void Function(Position)? _previousCallback;

  @override
  void initState() {
    super.initState();
    _previousCallback = widget.trackingService.onPositionUpdate;
    widget.trackingService.onPositionUpdate = (position) {
      setState(() {});
      _previousCallback?.call(position);
    };
  }

  @override
  void dispose() {
    widget.trackingService.onPositionUpdate = _previousCallback;
    super.dispose();
  }

  /// Convert m/s to mph.
  double _mpsToMph(double mps) => mps * 2.23694;

  /// Round up to a sensible y-axis max for mph/kph.
  double _roundUpMax(double value) {
    if (value <= 0) {
      return 5;
    }
    if (value <= 5) {
      return 5;
    }
    return (value / 5).ceil() * 5.0;
  }

  /// Filter speed history by the selected time window.
  List<SpeedDataPoint> _filteredPoints() {
    final history = widget.trackingService.speedHistory;
    if (history.isEmpty) {
      return [];
    }

    if (_timeWindow.duration == null) {
      return history;
    }

    final windowMs = _timeWindow.duration!.inMilliseconds;
    final latestMs = history.last.msSinceStart;
    final cutoffMs = latestMs - windowMs;
    return history.where((p) => p.msSinceStart >= cutoffMs).toList();
  }

  Color _barColorForAccuracy(double accuracyMeters) {
    if (accuracyMeters <= 5) {
      return Colors.green;
    }
    if (accuracyMeters <= 20) {
      return Colors.yellow;
    }
    return Colors.red;
  }

  Widget _buildChart() {
    final points = _filteredPoints();

    if (points.isEmpty) {
      return const Center(
        child: Text(
          'No speed data yet.\nStart moving to see the chart.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final speeds = points.map((p) => _mpsToMph(p.speedMps)).toList();
    final maxSpeed = speeds.reduce(max);
    final yMax = _roundUpMax(maxSpeed);

    // X-axis: time in seconds since first point in window.
    final firstMs = points.first.msSinceStart;

    if (_chartMode == _ChartMode.line) {
      return _buildLineChart(points, firstMs, yMax);
    } else {
      return _buildBarChart(points, firstMs, yMax);
    }
  }

  Widget _buildLineChart(
    List<SpeedDataPoint> points,
    int firstMs,
    double yMax,
  ) {
    final spots = points.map((p) {
      return FlSpot(
        (p.msSinceStart - firstMs) / 1000.0,
        _mpsToMph(p.speedMps),
      );
    }).toList();

    final xMax = spots.last.x;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: yMax,
        minX: spots.first.x,
        maxX: xMax,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final secs = value.toInt();
                final m = secs ~/ 60;
                final s = secs % 60;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '$m:${s.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == yMax) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: Colors.green,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withAlpha(40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(
    List<SpeedDataPoint> points,
    int firstMs,
    double yMax,
  ) {
    // Filter out points with no speed (speed <= 0).
    final validPoints = points.where((p) => p.speedMps > 0).toList();

    if (validPoints.isEmpty) {
      return const Center(
        child: Text(
          'No speed data to display.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < validPoints.length; i++) {
      final p = validPoints[i];
      final mph = _mpsToMph(p.speedMps);
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: mph,
              color: _barColorForAccuracy(p.accuracyMeters),
              width: max(2.0, 200.0 / validPoints.length).clamp(2.0, 16.0),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: yMax,
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= validPoints.length) {
                  return const SizedBox.shrink();
                }
                // Show ~5 labels max.
                final step = max(1, validPoints.length ~/ 5);
                if (idx % step != 0 && idx != validPoints.length - 1) {
                  return const SizedBox.shrink();
                }
                final secs = (validPoints[idx].msSinceStart - firstMs) ~/ 1000;
                final m = secs ~/ 60;
                final s = secs % 60;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '$m:${s.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == yMax) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _filteredPoints();
    final speeds = points.map((p) => _mpsToMph(p.speedMps)).toList();
    final maxSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(max);
    final yMax = _roundUpMax(maxSpeed);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Speedometer'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Y-axis key
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Max: ${yMax.toInt()} mph',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  'Current: ${speeds.isEmpty ? "—" : speeds.last.toStringAsFixed(1)} mph',
                  style: const TextStyle(color: Colors.green, fontSize: 14),
                ),
              ],
            ),
          ),
          // Chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              child: _buildChart(),
            ),
          ),
          // Bar chart legend
          if (_chartMode == _ChartMode.bar) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(Colors.green, '<5m'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.yellow, '5-20m'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.red, '>20m'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Controls row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Chart mode toggle
                ToggleButtons(
                  isSelected: [
                    _chartMode == _ChartMode.line,
                    _chartMode == _ChartMode.bar,
                  ],
                  onPressed: (index) {
                    setState(() {
                      _chartMode =
                          index == 0 ? _ChartMode.line : _ChartMode.bar;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.black,
                  fillColor: Colors.green,
                  color: Colors.grey,
                  constraints: const BoxConstraints(
                    minHeight: 36,
                    minWidth: 56,
                  ),
                  children: const [
                    Text('Line'),
                    Text('Bar'),
                  ],
                ),
                const Spacer(),
                // Time window selector
                DropdownButton<_TimeWindow>(
                  value: _timeWindow,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  underline: Container(height: 1, color: Colors.grey),
                  items: _TimeWindow.values.map((tw) {
                    return DropdownMenuItem(
                      value: tw,
                      child: Text(tw.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _timeWindow = value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
