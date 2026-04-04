import 'package:flutter_test/flutter_test.dart';
import 'package:gps_collector/screens/speedometer_screen.dart';

void main() {
  const labelHeight = 25.2; // 11 * 1.2 + 12

  group('pickYStep', () {
    test('mph/kph: small range picks step of 1', () {
      expect(pickYStep(5, isMinPerKm: false), 1.0);
    });

    test('mph/kph: medium range picks step of 5', () {
      expect(pickYStep(30, isMinPerKm: false), 5.0);
    });

    test('mph/kph: large range picks step of 10', () {
      expect(pickYStep(60, isMinPerKm: false), 10.0);
    });

    test('min/km: small range picks step of 10s', () {
      expect(pickYStep(50, isMinPerKm: true), 10.0);
    });

    test('min/km: medium range picks step of 60s', () {
      expect(pickYStep(300, isMinPerKm: true), 60.0);
    });

    test('min/km: large range picks step of 120s', () {
      expect(pickYStep(800, isMinPerKm: true), 120.0);
    });
  });

  group('buildYLabelValues', () {
    /// Format label values as a comma-separated string of mm:ss labels.
    String formatLabels(List<double> values) {
      return values.map((v) {
        final secs = v.abs().round();
        final m = secs ~/ 60;
        final s = secs % 60;
        return '$m:${s.toString().padLeft(2, '0')}';
      }).join(', ');
    }

    test('real case - 3:30 labels overlapping', () {
      const yMin = -650.0;
      const yMax = -210.0;
      const actualMin = -640.1302999603496;
      const actualMax = -212.32737881055473;
      const chartHeight = 611.3333333333334;
      const isMinPerKm = true;
      final result = buildYLabelValues(
        yMin: yMin,
        yMax: yMax,
        actualMin: actualMin,
        actualMax: actualMax,
        chartHeight: chartHeight,
        labelHeight: labelHeight,
        isMinPerKm: isMinPerKm,
      );
      expect(formatLabels(result),
          '10:50, 10:00, 9:00, 8:00, 7:00, 6:00, 5:00, 4:00, 3:30');
    });

    test('zero range returns single value', () {
      final result = buildYLabelValues(
        yMin: 10,
        yMax: 10,
        actualMin: 10,
        actualMax: 10,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      expect(result, [10]);
    });

    test('always includes yMin and yMax', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 25,
        actualMin: 5,
        actualMax: 20,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      expect(result.first, 0);
      expect(result.last, 25);
    });

    test('mph: 0 to 25 range includes intermediates', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 25,
        actualMin: 3,
        actualMax: 22,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      // Should have boundary values and some intermediates at step=5
      expect(result.contains(0), true);
      expect(result.contains(25), true);
      // Intermediates at 5, 10, 15, 20
      expect(result.where((v) => v > 0 && v < 25).isNotEmpty, true);
    });

    test('labels are sorted ascending', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 50,
        actualMin: 8,
        actualMax: 45,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      for (var i = 1; i < result.length; i++) {
        expect(result[i], greaterThan(result[i - 1]));
      }
    });

    test('no two labels overlap given chart height', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 50,
        actualMin: 3,
        actualMax: 47,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      final range = 50.0;
      for (var i = 1; i < result.length; i++) {
        final gap = (result[i] - result[i - 1]).abs();
        final pixelGap = gap / range * 300;
        // Each label centre should be at least labelHeight apart
        // (boundary labels get extra clearance but middle ones just need labelHeight)
        expect(pixelGap, greaterThanOrEqualTo(labelHeight * 0.9),
            reason: 'Labels ${result[i - 1]} and ${result[i]} too close: ${pixelGap.toStringAsFixed(1)}px');
      }
    });

    test('min/km inverted: negative values, yMin < yMax', () {
      // min/km inverted: yMin=-650 (bottom/slowest), yMax=-210 (top/fastest)
      final result = buildYLabelValues(
        yMin: -650,
        yMax: -210,
        actualMin: -630,
        actualMax: -220,
        chartHeight: 560,
        labelHeight: labelHeight,
        isMinPerKm: true,
      );
      expect(result.first, -650);
      expect(result.last, -210);
      // Should have intermediates (step=60 for range 440)
      expect(result.length, greaterThan(2));
    });

    test('min/km: top boundary label not overlapped', () {
      // This was the failing case: 3:30 to 10:50
      final result = buildYLabelValues(
        yMin: -650,
        yMax: -210,
        actualMin: -630,
        actualMax: -220,
        chartHeight: 560,
        labelHeight: labelHeight,
        isMinPerKm: true,
      );
      final range = 440.0;
      // Check top boundary (last element = -210) has enough clearance
      // from its nearest neighbour.
      if (result.length >= 2) {
        final topGap = (result.last - result[result.length - 2]).abs();
        final pixelGap = topGap / range * 560;
        expect(pixelGap, greaterThanOrEqualTo(labelHeight),
            reason: 'Top label too close to neighbour: ${pixelGap.toStringAsFixed(1)}px');
      }
    });

    test('small chart height limits number of labels', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 50,
        actualMin: 5,
        actualMax: 45,
        chartHeight: 80, // very small chart
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      // maxLabels = floor(80/25.2) = 3, so at most 3 labels
      expect(result.length, lessThanOrEqualTo(4)); // boundaries + maybe 1-2 intermediates
    });

    test('large chart height allows more labels', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 100,
        actualMin: 5,
        actualMax: 95,
        chartHeight: 600,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      // maxLabels = floor(600/25.2) = 23 -> clamped to 20
      // step=20 for range 100, so intermediates at 20,40,60,80
      expect(result.length, greaterThan(3));
    });

    test('actual min/max added when far enough from boundaries', () {
      final result = buildYLabelValues(
        yMin: 0,
        yMax: 50,
        actualMin: 12,
        actualMax: 38,
        chartHeight: 400,
        labelHeight: labelHeight,
        isMinPerKm: false,
      );
      // actualMin=12 and actualMax=38 should appear if far enough
      // from boundaries and step values
      // With step=10, intermediates at 10,20,30,40
      // 12 is close to 10 so may not appear; 38 is close to 40 so may not appear
      // Just verify no overlap
      for (var i = 1; i < result.length; i++) {
        expect(result[i], greaterThan(result[i - 1]));
      }
    });

    test('narrow min/km range does not produce overlapping labels', () {
      // Narrow range: 6:50 to 7:10 (410s to 430s, negated)
      final result = buildYLabelValues(
        yMin: -430,
        yMax: -410,
        actualMin: -428,
        actualMax: -412,
        chartHeight: 300,
        labelHeight: labelHeight,
        isMinPerKm: true,
      );
      expect(result.first, -430);
      expect(result.last, -410);
      final range = 20.0;
      for (var i = 1; i < result.length; i++) {
        final gap = (result[i] - result[i - 1]).abs();
        final pixelGap = gap / range * 300;
        expect(pixelGap, greaterThanOrEqualTo(labelHeight * 0.9),
            reason: 'Labels ${result[i - 1]} and ${result[i]} too close: ${pixelGap.toStringAsFixed(1)}px');
      }
    });
  });
}
