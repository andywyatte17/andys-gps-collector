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

/// Pick a round step for intermediate y-axis labels.
/// [isMinPerKm] true when the unit is min/km (range is in seconds).
double pickYStep(double range, {required bool isMinPerKm}) {
  if (isMinPerKm) {
    final absRange = range.abs();
    const candidates = [10.0, 30.0, 60.0, 120.0, 300.0, 600.0];
    for (final c in candidates) {
      if (absRange / c <= 8) {
        return c;
      }
    }
    return 600.0;
  }
  const candidates = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
  for (final c in candidates) {
    if (range / c <= 8) {
      return c;
    }
  }
  return 50.0;
}

/// Build the set of y-axis values that should be labelled.
/// Includes boundary values (yMin, yMax), evenly-spaced intermediates,
/// and actual min/max of visible data — with overlap removal.
///
/// [labelHeight] is the estimated pixel height of a single label.
/// [chartHeight] is the available pixel height for the chart plot area.
List<double> buildYLabelValues({
  required double yMin,
  required double yMax,
  required double actualMin,
  required double actualMax,
  required double chartHeight,
  required double labelHeight,
  required bool isMinPerKm,
}) {
  final range = (yMax - yMin).abs();
  if (range == 0) {
    return [yMin];
  }

  final maxLabels = (chartHeight / labelHeight).floor().clamp(2, 20);
  final minGap = range / maxLabels;

  // Start with boundary values.
  final values = <double>[yMin, yMax];

  // Add evenly-spaced intermediate points.
  final step = pickYStep(range, isMinPerKm: isMinPerKm);
  if (step > 0) {
    final low = min(yMin, yMax);
    final high = max(yMin, yMax);
    var v = (low / step).ceil() * step;
    while (v < high) {
      values.add(v);
      v += step;
    }
  }

  // Add actual min/max if they differ enough from all existing labels.
  for (final v in [actualMin, actualMax]) {
    if (values.every((existing) => (existing - v).abs() > minGap)) {
      values.add(v);
    }
  }

  // Sort and remove any labels that are too close to the top or bottom
  // boundaries, or to their neighbour. yMin and yMax always survive.
  // Boundary labels sit at the very edge (py=0 or py=chartHeight),
  // so intermediates need extra clearance to avoid overlapping them.
  final edgeClearance = (labelHeight * 1.5) / chartHeight * range;
  final boundaryGap = max(minGap, edgeClearance);

  values.sort();
  final bottom = values.first;
  final top = values.last;
  final result = <double>[bottom];
  for (var i = 1; i < values.length - 1; i++) {
    final v = values[i];
    final tooCloseToBottom = (v - bottom).abs() < boundaryGap;
    final tooCloseToTop = (top - v).abs() < boundaryGap;
    final tooCloseToPrev = (v - result.last).abs() < minGap;
    if (!tooCloseToBottom && !tooCloseToTop && !tooCloseToPrev) {
      result.add(v);
    }
  }
  if (values.length > 1) {
    result.add(top);
  }
  return result;
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
  /// Delegate to top-level [buildYLabelValues].
  static const _labelFontSize = 11.0;
  static const _labelHeight = _labelFontSize * 1.2 + 12.0;

  List<double> _buildYLabelValues(
    double yMin,
    double yMax,
    double actualMin,
    double actualMax,
    double chartHeight,
  ) {
    final result = buildYLabelValues(
      yMin: yMin,
      yMax: yMax,
      actualMin: actualMin,
      actualMax: actualMax,
      chartHeight: chartHeight,
      labelHeight: _labelHeight,
      isMinPerKm: _speedUnit == _SpeedUnit.minPerKm,
    );

    return result;
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

    // Build tap-to-inspect label (history/static mode only).
    Widget? inspectLabel;
    if (!widget.isLive && _selectedPointIndex != null) {
      final idx = _selectedPointIndex!;
      if (idx >= 0 && idx < points.length) {
        final p = points[idx];
        final v = _convertSpeed(p.speedMps);
        if (v != null) {
          final timeStr = _formatInspectTime(p.msSinceStart, firstMs, lastMs);
          final valStr = _formatValue(v);
          final isDark = Theme.of(context).brightness == Brightness.dark;
          inspectLabel = Text(
            '$timeStr  /  $valStr ${_speedUnit.label}',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartHeight = constraints.maxHeight;
              if (_chartMode == _ChartMode.line) {
                return _buildLineChart(points, firstMs, yMin, yMax,
                    _isInverted ? -maxSpeed : minSpeed,
                    _isInverted ? -minSpeed : maxSpeed,
                    chartHeight);
              } else {
                return _buildBarChart(points, firstMs, yMin, yMax,
                    _isInverted ? -maxSpeed : minSpeed,
                    _isInverted ? -minSpeed : maxSpeed,
                    chartHeight);
              }
            },
          ),
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
    double chartHeight,
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

    // Pre-compute x-axis labels at interval steps, suppressing labels
    // too close to edges. Build a map keyed by step index.
    final xLabelWidgets = <int, Widget>{};
    final xBoundaryIndices = <int>{};
    if (xInterval > 0 && xRange > 0) {
      // Generate label values at xInterval steps from xMin to xMax.
      final xValues = <double>[];
      var xv = xMin;
      while (xv <= xMax + xInterval * 0.01) {
        xValues.add(xv);
        xv += xInterval;
      }
      // Always include xMin and xMax.
      if (xValues.isEmpty || (xValues.first - xMin).abs() > 0.01) {
        xValues.insert(0, xMin);
      }
      if ((xValues.last - xMax).abs() > 0.01) {
        xValues.add(xMax);
      }

      for (final v in xValues) {
        // Suppress labels too close to edges (but keep first/last).
        final isFirst = (v - xMin).abs() < 0.01;
        final isLast = (v - xMax).abs() < 0.01;
        if (!isFirst && !isLast) {
          if (v - xMin < xInterval * 0.4) {
            continue;
          }
          if (xMax - v < xInterval * 0.4) {
            continue;
          }
        }
        final idx = ((v - xMin) / xInterval).round();
        final absSecs = v.abs().toInt();
        final m = absSecs ~/ 60;
        final s = absSecs % 60;
        final timeStr = '$m:${s.toString().padLeft(2, '0')}';
        final label = v >= -0.01 ? timeStr : '-$timeStr';
        xLabelWidgets[idx] = SideTitleWidget(
          axisSide: AxisSide.bottom,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
        );
        if (isFirst || isLast) {
          xBoundaryIndices.add(idx);
        }
      }
    }

    // Y-axis labels: boundary values + actual min/max.
    final yLabelValues = _buildYLabelValues(yMin, yMax, actualMin, actualMax, chartHeight);

    // Pre-build a map from sample index → label widget for the y-axis.
    final yStep = (yMax - yMin).abs() / 100;
    final yLabelWidgets = <int, Widget>{};
    // Track which label indices sit exactly on a boundary (yMin or yMax).
    final yBoundaryIndices = <int>{};
    for (final lv in yLabelValues) {
      final idx = ((lv - yMin) / yStep).round();
      yLabelWidgets[idx] = SideTitleWidget(
        axisSide: AxisSide.left,
        child: Text(
          _formatMaxLabel(lv.abs()),
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
      if ((lv - yMin).abs() < 0.01 || (lv - yMax).abs() < 0.01) {
        yBoundaryIndices.add(idx);
      }
    }

    // Extra horizontal grid lines for labelled y values.
    final horizontalLines = yLabelValues.map((v) {
      return HorizontalLine(
        y: v,
        color: Colors.grey.withAlpha(90),
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
                if (xInterval <= 0) {
                  return const SizedBox.shrink();
                }
                final idx = ((value - xMin) / xInterval).round();
                final widget = xLabelWidgets[idx];
                if (widget == null) {
                  return const SizedBox.shrink();
                }
                if (xBoundaryIndices.contains(idx)) {
                  final boundaryValue = idx == 0 ? xMin : xMax;
                  if ((value - boundaryValue).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                }
                return widget;
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: (yMax - yMin).abs() > 0
                  ? (yMax - yMin).abs() / 100
                  : 1,
              getTitlesWidget: (value, meta) {
                final yStep = (yMax - yMin).abs() / 100;
                if (yStep == 0) {
                  return const SizedBox.shrink();
                }
                final idx = ((value - yMin) / yStep).round();
                final widget = yLabelWidgets[idx];
                if (widget == null) {
                  return const SizedBox.shrink();
                }
                // For boundary labels (yMin/yMax), prefer the exact
                // boundary call over the grid step to avoid double-render.
                if (yBoundaryIndices.contains(idx)) {
                  final boundaryValue = idx == 0 ? yMin : yMax;
                  if ((value - boundaryValue).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                }
                return widget;
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: !widget.isLive,
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (widget.isLive) {
              return;
            }
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
            isCurved: false,
            color: Colors.green,
            barWidth: 2,
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
    double chartHeight,
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
      final baseColor = _barColorForAccuracy(p.accuracyMeters);
      final barColor = isSelected
          ? Color.lerp(baseColor, Colors.white, 0.45)!
          : baseColor;
      final barWidth = max(2.0, 200.0 / validPoints.length).clamp(2.0, 16.0);
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              fromY: yMin,
              toY: plotValue,
              color: barColor,
              width: isSelected ? barWidth + 2 : barWidth,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
            ),
          ],
        ),
      );
    }

    // Pre-compute bar chart x-axis labels, deduplicating by label text.
    final barXLabelWidgets = <int, Widget>{};
    {
      final step = max(1, validPoints.length ~/ 5);
      final shownLabels = <String>{};
      // Collect candidate indices (step-based + last).
      final candidates = <int>[];
      for (var i = 0; i < validPoints.length; i += step) {
        candidates.add(i);
      }
      if (validPoints.isNotEmpty) {
        final last = validPoints.length - 1;
        if (!candidates.contains(last)) {
          // Suppress last if too close to nearest stepped label.
          final nearestStep = (last ~/ step) * step;
          if (last - nearestStep >= step * 0.6) {
            candidates.add(last);
          }
        }
      }
      for (final idx in candidates) {
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
        // Skip if this label text was already shown.
        if (shownLabels.contains(label)) {
          continue;
        }
        shownLabels.add(label);
        barXLabelWidgets[idx] = SideTitleWidget(
          axisSide: AxisSide.bottom,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
        );
      }
    }

    // Y-axis labels: boundary values + actual min/max.
    final yLabelValues = _buildYLabelValues(yMin, yMax, actualMin, actualMax, chartHeight);

    // Pre-build a map from sample index → label widget for the y-axis.
    final yStep = (yMax - yMin).abs() / 100;
    final yLabelWidgets = <int, Widget>{};
    final yBoundaryIndices = <int>{};
    for (final lv in yLabelValues) {
      final idx = ((lv - yMin) / yStep).round();
      yLabelWidgets[idx] = SideTitleWidget(
        axisSide: AxisSide.left,
        child: Text(
          _formatMaxLabel(lv.abs()),
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
      if ((lv - yMin).abs() < 0.01 || (lv - yMax).abs() < 0.01) {
        yBoundaryIndices.add(idx);
      }
    }

    return BarChart(
      BarChartData(
            maxY: yMax,
            minY: yMin,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: !widget.isLive,
          touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
            if (widget.isLive) {
              return;
            }
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
                return barXLabelWidgets[value.toInt()] ?? const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: (yMax - yMin).abs() > 0
                  ? (yMax - yMin).abs() / 100
                  : 1,
              getTitlesWidget: (value, meta) {
                final yStep = (yMax - yMin).abs() / 100;
                if (yStep == 0) {
                  return const SizedBox.shrink();
                }
                final idx = ((value - yMin) / yStep).round();
                final widget = yLabelWidgets[idx];
                if (widget == null) {
                  return const SizedBox.shrink();
                }
                // For boundary labels (yMin/yMax), prefer the exact
                // boundary call over the grid step to avoid double-render.
                if (yBoundaryIndices.contains(idx)) {
                  final boundaryValue = idx == 0 ? yMin : yMax;
                  if ((value - boundaryValue).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                }
                return widget;
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final appBarBg = theme.appBarTheme.backgroundColor ?? scaffoldBg;
    final appBarFg = theme.appBarTheme.foregroundColor ??
        (isDark ? Colors.white : Colors.black);
    final textColor = isDark ? Colors.white : Colors.black;
    final subtleColor = isDark ? Colors.grey : Colors.grey.shade600;

    if (_loadingHistory) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          title: const Text('Speedometer'),
          backgroundColor: appBarBg,
          foregroundColor: appBarFg,
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
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
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
                  style: TextStyle(color: textColor, fontSize: 14),
                ),
                const Spacer(),
                if (widget.isLive)
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
                Flexible(
                  child: ToggleButtons(
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
                    selectedColor: isDark ? Colors.black : Colors.white,
                    fillColor: Colors.green,
                    color: subtleColor,
                    constraints: const BoxConstraints(
                      minHeight: 36,
                      minWidth: 48,
                    ),
                    children: const [
                      Text('Line'),
                      Text('Bar'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                    foregroundColor: textColor,
                    side: BorderSide(color: subtleColor),
                    minimumSize: const Size(56, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    foregroundColor: textColor,
                    side: BorderSide(color: subtleColor),
                    minimumSize: const Size(56, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
        Text(label, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }
}

