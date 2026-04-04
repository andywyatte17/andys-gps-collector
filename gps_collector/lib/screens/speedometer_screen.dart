import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import '../services/tracking_service.dart';

enum _ChartMode { line, bar }

enum _SpeedUnit {
  mph('mph'),
  kph('kph'),
  minPerKm('min/km');

  final String label;
  const _SpeedUnit(this.label);
}

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
  _SpeedUnit _speedUnit = _SpeedUnit.mph;

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

  /// Convert m/s to the selected display unit.
  /// For min/km, returns seconds-per-km (displayed as mm:ss).
  /// Returns null for min/km when speed is effectively zero.
  double? _convertSpeed(double mps) {
    switch (_speedUnit) {
      case _SpeedUnit.mph:
        return mps * 2.23694;
      case _SpeedUnit.kph:
        return mps * 3.6;
      case _SpeedUnit.minPerKm:
        if (mps < 0.1) {
          return null; // stationary — no meaningful pace
        }
        return 1000.0 / mps; // seconds per km
    }
  }

  /// Round up to a sensible y-axis max.
  /// For mph/kph: round up to nearest multiple of 5.
  /// For min/km (seconds): round up to nearest 10 seconds.
  double _roundUpMax(double value) {
    if (_speedUnit == _SpeedUnit.minPerKm) {
      if (value <= 0) {
        return 600; // 10 minutes
      }
      return (value / 10).ceil() * 10.0;
    }
    if (value <= 0) {
      return 5;
    }
    if (value <= 5) {
      return 5;
    }
    return (value / 5).ceil() * 5.0;
  }

  /// Format a display value as a string for the y-axis / header.
  String _formatValue(double value) {
    if (_speedUnit == _SpeedUnit.minPerKm) {
      final totalSecs = value.round();
      final m = totalSecs ~/ 60;
      final s = totalSecs % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return value.toStringAsFixed(1);
  }

  /// Format the y-axis max label (integer for mph/kph, mm:ss for min/km).
  String _formatMaxLabel(double value) {
    if (_speedUnit == _SpeedUnit.minPerKm) {
      final totalSecs = value.round();
      final m = totalSecs ~/ 60;
      final s = totalSecs % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return value.toInt().toString();
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

  /// Pick a round time interval (in seconds) that yields ~4-6 labels
  /// across the given x-axis range (also in seconds).
  double _pickTimeInterval(double rangeSeconds) {
    if (rangeSeconds <= 0) {
      return 10;
    }
    // Candidate intervals: 5s, 10s, 15s, 30s, 1m, 2m, 5m, 10m, 30m
    const candidates = [5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0, 600.0, 1800.0];
    for (final c in candidates) {
      if (rangeSeconds / c <= 6) {
        return c;
      }
    }
    return 1800.0;
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

    final speeds = points
        .map((p) => _convertSpeed(p.speedMps))
        .where((v) => v != null)
        .cast<double>()
        .toList();

    if (speeds.isEmpty) {
      return const Center(
        child: Text(
          'No speed data to display.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

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
    final spots = points
        .where((p) => _convertSpeed(p.speedMps) != null)
        .map((p) {
      return FlSpot(
        (p.msSinceStart - firstMs) / 1000.0,
        _convertSpeed(p.speedMps)!,
      );
    }).toList();

    if (spots.isEmpty) {
      return const Center(
        child: Text(
          'No speed data to display.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final xMin = spots.first.x;
    final xMax = spots.last.x;
    final xRange = xMax - xMin;

    // Choose a label interval that yields roughly 4-6 labels,
    // snapping to round time boundaries.
    final xInterval = _pickTimeInterval(xRange);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: yMax,
        minX: xMin,
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
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                // Suppress labels too close to either edge to avoid overlap.
                if (value - xMin < xInterval * 0.4 && value != xMin) {
                  return const SizedBox.shrink();
                }
                if (xMax - value < xInterval * 0.4 && value != xMax) {
                  return const SizedBox.shrink();
                }
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
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == yMax) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _formatMaxLabel(value),
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
    // Filter out points with no displayable speed.
    final validPoints = points
        .where((p) => _convertSpeed(p.speedMps) != null && p.speedMps > 0)
        .toList();

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
      final displayValue = _convertSpeed(p.speedMps)!;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: displayValue,
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
                // Target ~5 labels. Compute step and suppress the
                // last-index label if it's too close to a stepped one.
                final step = max(1, validPoints.length ~/ 5);
                final isStepLabel = idx % step == 0;
                final isLastLabel = idx == validPoints.length - 1;
                if (!isStepLabel && !isLastLabel) {
                  return const SizedBox.shrink();
                }
                // Suppress last label if it's within half a step of the
                // nearest stepped label — prevents overlap at the end.
                if (isLastLabel && !isStepLabel) {
                  final nearestStep = (idx ~/ step) * step;
                  if (idx - nearestStep < step * 0.6) {
                    return const SizedBox.shrink();
                  }
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
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == yMax) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _formatMaxLabel(value),
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
    final speeds = points
        .map((p) => _convertSpeed(p.speedMps))
        .where((v) => v != null)
        .cast<double>()
        .toList();
    final maxSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(max);
    final yMax = _roundUpMax(maxSpeed);
    final unitLabel = _speedUnit.label;

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
                  'Max: ${_formatMaxLabel(yMax)} $unitLabel',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  'Current: ${speeds.isEmpty ? "—" : _formatValue(speeds.last)} $unitLabel',
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
                const SizedBox(width: 12),
                // Speed unit — tap to cycle
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      final values = _SpeedUnit.values;
                      _speedUnit = values[(_speedUnit.index + 1) % values.length];
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.grey),
                    minimumSize: const Size(64, 36),
                  ),
                  child: Text(_speedUnit.label),
                ),
                const Spacer(),
                // Time window — tap to cycle
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      final values = _TimeWindow.values;
                      _timeWindow = values[(_timeWindow.index + 1) % values.length];
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.grey),
                    minimumSize: const Size(64, 36),
                  ),
                  child: Text(_timeWindow.label),
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
