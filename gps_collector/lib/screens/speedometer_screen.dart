import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import '../services/database_service.dart';
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
  /// Live mode: provide a TrackingService for real-time updates.
  final TrackingService? trackingService;

  /// Historical mode: provide a trackId to load past data from the DB.
  final int? trackId;
  final String? trackName;

  const SpeedometerScreen.live({
    super.key,
    required this.trackingService,
  })  : trackId = null,
        trackName = null;

  const SpeedometerScreen.history({
    super.key,
    required this.trackId,
    this.trackName,
  })  : trackingService = null;

  bool get isLive => trackingService != null;

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  _ChartMode _chartMode = _ChartMode.line;
  _TimeWindow _timeWindow = _TimeWindow.all;
  _SpeedUnit _speedUnit = _SpeedUnit.mph;

  // Tap-to-inspect: index of the tapped point (null = nothing selected).
  int? _selectedPointIndex;

  // Live mode: store the previous callback so we can restore it on dispose.
  void Function(Position)? _previousCallback;

  // Historical mode: loaded data points.
  List<SpeedDataPoint>? _historicalPoints;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    if (widget.isLive) {
      _previousCallback = widget.trackingService!.onPositionUpdate;
      widget.trackingService!.onPositionUpdate = (position) {
        setState(() {});
        _previousCallback?.call(position);
      };
    } else {
      _loadHistoricalData();
    }
  }

  @override
  void dispose() {
    if (widget.isLive) {
      widget.trackingService!.onPositionUpdate = _previousCallback;
    }
    super.dispose();
  }

  Future<void> _loadHistoricalData() async {
    setState(() {
      _loadingHistory = true;
    });
    final db = DatabaseService();
    final events = await db.getTrackPoints(trackId: widget.trackId!);
    final points = <SpeedDataPoint>[];
    for (final e in events) {
      final speed = e['speed'] as double?;
      final accuracy = e['accuracy_meters'] as double?;
      final ms = e['ms_since_start'] as int;
      if (speed != null && speed >= 0) {
        points.add(SpeedDataPoint(
          msSinceStart: ms,
          speedMps: speed,
          accuracyMeters: accuracy ?? 0,
        ));
      }
    }
    setState(() {
      _historicalPoints = points;
      _loadingHistory = false;
    });
  }

  /// Get the current speed data points depending on mode.
  List<SpeedDataPoint> _allPoints() {
    if (widget.isLive) {
      return widget.trackingService!.speedHistory;
    }
    return _historicalPoints ?? [];
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

  /// Whether the y-axis is inverted (min/km: lower value = faster = top).
  bool get _isInverted => _speedUnit == _SpeedUnit.minPerKm;

  /// Round up to a sensible y-axis boundary.
  /// For mph/kph: round up to nearest multiple of 5.
  /// For min/km (seconds): round up to nearest 10 seconds.
  double _roundUp(double value) {
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

  /// Round down to a sensible y-axis boundary.
  /// For mph/kph: round down to nearest multiple of 5 (min 0).
  /// For min/km (seconds): round down to nearest 10 seconds.
  double _roundDown(double value) {
    if (_speedUnit == _SpeedUnit.minPerKm) {
      if (value <= 0) {
        return 0;
      }
      return (value / 10).floor() * 10.0;
    }
    if (value <= 0) {
      return 0;
    }
    return (value / 5).floor() * 5.0;
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
    final history = _allPoints();
    if (history.isEmpty) {
      return [];
    }

    if (_timeWindow.duration == null) {
      return history;
    }

    final windowMs = _timeWindow.duration!.inMilliseconds;
    final latestMs = history.last.msSinceStart;
    final cutoffMs = latestMs - windowMs;
    // Include one point just before the window so the chart spans
    // the full duration even when no point falls exactly on the boundary.
    int startIndex = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].msSinceStart < cutoffMs) {
        startIndex = i;
        break;
      }
    }
    return history.sublist(startIndex);
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

  /// Build the set of y-axis values that should be labelled and have
  /// dotted horizontal lines drawn. Includes boundary values and
  /// actual min/max of visible data (deduplicated).
  List<double> _buildYLabelValues(
    double yMin,
    double yMax,
    double actualMin,
    double actualMax,
  ) {
    final values = <double>{yMin, yMax};
    // Add actual min/max if they differ enough from boundaries.
    final range = (yMax - yMin).abs();
    final threshold = range * 0.05; // 5% of range to avoid overlapping labels
    for (final v in [actualMin, actualMax]) {
      if (values.every((existing) => (existing - v).abs() > threshold)) {
        values.add(v);
      }
    }
    final sorted = values.toList()..sort();
    return sorted;
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

  /// Format the time for the tap-to-inspect label, using the same
  /// convention as the x-axis (absolute for All, relative for others).
  String _formatInspectTime(int msSinceStart, int firstMs, int lastMs) {
    if (_timeWindow == _TimeWindow.all) {
      final secs = (msSinceStart - firstMs) / 1000.0;
      final absSecs = secs.abs().toInt();
      final m = absSecs ~/ 60;
      final s = absSecs % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    } else {
      final secs = (msSinceStart - lastMs) / 1000.0;
      final absSecs = secs.abs().toInt();
      final m = absSecs ~/ 60;
      final s = absSecs % 60;
      final timeStr = '$m:${s.toString().padLeft(2, '0')}';
      return secs >= -0.01 ? timeStr : '-$timeStr';
    }
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

    // Build list of valid (index, convertedSpeed) pairs.
    final validEntries = <(int, double)>[];
    for (var i = 0; i < points.length; i++) {
      final v = _convertSpeed(points[i].speedMps);
      if (v != null) {
        validEntries.add((i, v));
      }
    }

    if (validEntries.isEmpty) {
      return const Center(
        child: Text(
          'No speed data to display.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final speeds = validEntries.map((e) => e.$2).toList();
    final maxSpeed = speeds.reduce(max);
    final minSpeed = speeds.reduce(min);

    // Compute y-axis bounds.
    // For min/km we negate all values so fl_chart draws fastest pace at top.
    // Labels use _formatMaxLabel on absolute values to display correctly.
    double yMin;
    double yMax;
    if (_isInverted) {
      // Negated: -slowest (biggest number) becomes minY (bottom),
      //          -fastest (smallest number) becomes maxY (top).
      yMin = -_roundUp(maxSpeed);    // bottom of chart (slowest pace)
      yMax = -_roundDown(minSpeed);  // top of chart (fastest pace)
    } else {
      yMin = 0;
      yMax = _roundUp(maxSpeed);
    }

    final firstMs = points.first.msSinceStart;
    final lastMs = points.last.msSinceStart;

    // Build tap-to-inspect label.
    Widget? inspectLabel;
    if (_selectedPointIndex != null) {
      final idx = _selectedPointIndex!;
      if (idx >= 0 && idx < points.length) {
        final p = points[idx];
        final v = _convertSpeed(p.speedMps);
        if (v != null) {
          final timeStr = _formatInspectTime(p.msSinceStart, firstMs, lastMs);
          final valStr = _formatValue(v);
          inspectLabel = Text(
            '$timeStr  /  $valStr ${_speedUnit.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          );
        }
      }
    }

    return Column(
      children: [
        // Tap-to-inspect label area
        SizedBox(
          height: 22,
          child: inspectLabel != null
              ? Center(child: inspectLabel)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: _chartMode == _ChartMode.line
              ? _buildLineChart(points, firstMs, yMin, yMax,
                  _isInverted ? -maxSpeed : minSpeed,
                  _isInverted ? -minSpeed : maxSpeed)
              : _buildBarChart(points, firstMs, yMin, yMax,
                  _isInverted ? -maxSpeed : minSpeed,
                  _isInverted ? -minSpeed : maxSpeed),
        ),
      ],
    );
  }

  Widget _buildLineChart(
    List<SpeedDataPoint> points,
    int firstMs,
    double yMin,
    double yMax,
    double actualMin,
    double actualMax,
  ) {
    final lastMs = points.last.msSinceStart;
    final isAllWindow = _timeWindow == _TimeWindow.all;

    // Build spots with original index tracking for tap-to-inspect.
    final spotIndices = <int>[]; // maps spot index -> points index
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = _convertSpeed(points[i].speedMps);
      if (v == null) {
        continue;
      }
      final xVal = isAllWindow
          ? (points[i].msSinceStart - firstMs) / 1000.0
          : (points[i].msSinceStart - lastMs) / 1000.0;
      spots.add(FlSpot(xVal, _isInverted ? -v : v));
      spotIndices.add(i);
    }

    if (spots.isEmpty) {
      return const Center(
        child: Text(
          'No speed data to display.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    // X-axis bounds.
    double xMin, xMax;
    if (isAllWindow) {
      xMin = 0;
      xMax = spots.last.x;
    } else {
      xMin = spots.first.x;
      xMax = 0; // always show 0:00 on the right
    }
    final xRange = xMax - xMin;
    final xInterval = _pickTimeInterval(xRange);

    // Y-axis labels: boundary values + actual min/max.
    final yLabelValues = _buildYLabelValues(yMin, yMax, actualMin, actualMax);

    // Extra horizontal grid lines for labelled y values.
    final horizontalLines = yLabelValues.map((v) {
      return HorizontalLine(
        y: v,
        color: Colors.grey.withAlpha(40),
        strokeWidth: 1,
        dashArray: [3, 5],
      );
    }).toList();

    // Highlight dot for selected point.
    final selectedSpotIndex = _selectedPointIndex != null
        ? spotIndices.indexOf(_selectedPointIndex!)
        : -1;

    return LineChart(
      LineChartData(
        minY: _isInverted ? yMin : yMin,
        maxY: yMax,
        minX: xMin,
        maxX: xMax,
        clipData: const FlClipData.all(),
        extraLinesData: ExtraLinesData(horizontalLines: horizontalLines),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: false,
          drawVerticalLine: true,
          verticalInterval: xInterval,
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.withAlpha(60),
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
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
                final isFirst = (value - xMin).abs() < 0.01;
                final isLast = (value - xMax).abs() < 0.01;
                if (!isFirst && !isLast) {
                  if (value - xMin < xInterval * 0.4) {
                    return const SizedBox.shrink();
                  }
                  if (xMax - value < xInterval * 0.4) {
                    return const SizedBox.shrink();
                  }
                }
                final absSecs = value.abs().toInt();
                final m = absSecs ~/ 60;
                final s = absSecs % 60;
                final timeStr = '$m:${s.toString().padLeft(2, '0')}';
                final label = value >= -0.01 ? timeStr : '-$timeStr';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    label,
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
                if (yLabelValues.any((v) => (v - value).abs() < 0.01)) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _formatMaxLabel(value.abs()),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent || event is FlLongPressEnd || event is FlPanUpdateEvent) {
              final spotIndex = response?.lineBarSpots?.firstOrNull?.spotIndex;
              if (spotIndex != null && spotIndex < spotIndices.length) {
                setState(() {
                  _selectedPointIndex = spotIndices[spotIndex];
                });
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            getTooltipItems: (_) => [null],
          ),
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((i) {
              return TouchedSpotIndicatorData(
                const FlLine(color: Colors.transparent),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 5,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: Colors.green,
                    );
                  },
                ),
              );
            }).toList();
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: Colors.green,
            barWidth: 2.5,
            dotData: FlDotData(
              show: selectedSpotIndex >= 0,
              checkToShowDot: (spot, barData) {
                if (selectedSpotIndex < 0) {
                  return false;
                }
                final selSpot = spots[selectedSpotIndex];
                return (spot.x - selSpot.x).abs() < 0.001 &&
                    (spot.y - selSpot.y).abs() < 0.001;
              },
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: Colors.green,
                );
              },
            ),
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
    double yMin,
    double yMax,
    double actualMin,
    double actualMax,
  ) {
    final lastMs = points.last.msSinceStart;
    final isAllWindow = _timeWindow == _TimeWindow.all;

    // Filter out points with no displayable speed, tracking original indices.
    final validIndices = <int>[];
    final validPoints = <SpeedDataPoint>[];
    for (var i = 0; i < points.length; i++) {
      if (_convertSpeed(points[i].speedMps) != null && points[i].speedMps > 0) {
        validIndices.add(i);
        validPoints.add(points[i]);
      }
    }

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
      final rawValue = _convertSpeed(p.speedMps)!;
      final plotValue = _isInverted ? -rawValue : rawValue;
      final isSelected = _selectedPointIndex == validIndices[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              fromY: _isInverted ? yMin : yMin,
              toY: plotValue,
              color: _barColorForAccuracy(p.accuracyMeters),
              width: max(2.0, 200.0 / validPoints.length).clamp(2.0, 16.0),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
              borderSide: isSelected
                  ? const BorderSide(color: Colors.white, width: 1.5)
                  : BorderSide.none,
            ),
          ],
        ),
      );
    }

    // Y-axis labels: boundary values + actual min/max.
    final yLabelValues = _buildYLabelValues(yMin, yMax, actualMin, actualMax);

    return BarChart(
      BarChartData(
        maxY: yMax,
        minY: yMin,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          checkToShowHorizontalLine: (value) {
            return yLabelValues.any((v) => (v - value).abs() < 0.01);
          },
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withAlpha(40),
              strokeWidth: 1,
              dashArray: [3, 5],
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
            if (event is FlTapUpEvent || event is FlLongPressEnd || event is FlPanUpdateEvent) {
              final barIdx = response?.spot?.touchedBarGroupIndex;
              if (barIdx != null && barIdx >= 0 && barIdx < validIndices.length) {
                setState(() {
                  _selectedPointIndex = validIndices[barIdx];
                });
              }
            }
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => null,
          ),
        ),
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
                final step = max(1, validPoints.length ~/ 5);
                final isStepLabel = idx % step == 0;
                final isLastLabel = idx == validPoints.length - 1;
                if (!isStepLabel && !isLastLabel) {
                  return const SizedBox.shrink();
                }
                if (isLastLabel && !isStepLabel) {
                  final nearestStep = (idx ~/ step) * step;
                  if (idx - nearestStep < step * 0.6) {
                    return const SizedBox.shrink();
                  }
                }
                int secs;
                if (isAllWindow) {
                  secs = (validPoints[idx].msSinceStart - firstMs) ~/ 1000;
                } else {
                  secs = (validPoints[idx].msSinceStart - lastMs) ~/ 1000;
                }
                final absSecs = secs.abs();
                final m = absSecs ~/ 60;
                final s = absSecs % 60;
                final timeStr = '$m:${s.toString().padLeft(2, '0')}';
                final label = secs >= 0 ? timeStr : '-$timeStr';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    label,
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
                if (yLabelValues.any((v) => (v - value).abs() < 0.01)) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      _formatMaxLabel(value.abs()),
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
    if (_loadingHistory) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Speedometer'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final points = _filteredPoints();
    final speeds = points
        .map((p) => _convertSpeed(p.speedMps))
        .where((v) => v != null)
        .cast<double>()
        .toList();
    final maxSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(max);
    final minSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(min);
    final unitLabel = _speedUnit.label;
    // For the header label: show peak speed (or best pace for min/km).
    final headerPeak = _isInverted ? minSpeed : maxSpeed;
    final title = widget.isLive
        ? 'Speedometer'
        : widget.trackName ?? 'Speedometer';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
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
                  '${_isInverted ? "Best" : "Max"}: ${_formatValue(headerPeak)} $unitLabel',
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
                      _selectedPointIndex = null;
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
                      _selectedPointIndex = null;
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
                      _selectedPointIndex = null;
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
