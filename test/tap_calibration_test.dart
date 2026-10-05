import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/tap_calibration.dart';

void main() {
  const beat = 0.5; // 120 BPM

  /// One hit per beat for [count] beats, each [offset] after its beat plus
  /// that beat's entry in [wobble] (cycled).
  List<double> hits(double offset, {int count = 16, List<double> wobble = const [0]}) => [
        for (var i = 0; i < count; i++) i * beat + offset + wobble[i % wobble.length],
      ];

  test('The offset is the average distance from each beat to its hit', () {
    final outcome = TapCalibration.measure(
      hitTimes: hits(0.13, wobble: [0.01, -0.01, 0.02, -0.02]),
      beatSeconds: beat,
    );

    expect(outcome.succeeded, isTrue);
    expect(outcome.offsetSeconds, closeTo(0.13, 0.001));
    expect(outcome.hitCount, 16);
    expect(outcome.spreadSeconds, closeTo(0.0158, 0.001));
  });

  test('Hits either side of the beat average to about zero, not half a beat', () {
    // Naively averaging "time since the last beat" would give ~250ms here.
    final outcome = TapCalibration.measure(
      hitTimes: hits(beat * 4, wobble: [0.015, -0.015]),
      beatSeconds: beat,
    );

    expect(outcome.offsetSeconds, closeTo(0, 0.001));
  });

  test('A slightly early average is reported as negative', () {
    final outcome = TapCalibration.measure(hitTimes: hits(beat * 4 - 0.03), beatSeconds: beat);

    expect(outcome.offsetSeconds, closeTo(-0.03, 0.001));
  });

  test('A long delay, as with Bluetooth headphones, is reported as late rather than early', () {
    final outcome = TapCalibration.measure(hitTimes: hits(0.32), beatSeconds: beat);

    expect(outcome.offsetSeconds, closeTo(0.32, 0.001));
  });

  test('A few stray hits are left out of the average', () {
    final outcome = TapCalibration.measure(
      hitTimes: [...hits(0.13), 1.37, 3.31, 5.02]..sort(),
      beatSeconds: beat,
    );

    expect(outcome.offsetSeconds, closeTo(0.13, 0.001));
    expect(outcome.hitCount, 16);
  });

  test('Hits before the measured part of the run are ignored', () {
    final outcome = TapCalibration.measure(
      // The first four beats are hit way off; the rest 130ms late.
      hitTimes: [0.3, 0.8, 1.3, 1.8, ...hits(0.13).skip(4)],
      beatSeconds: beat,
      fromSeconds: 4 * beat - 0.1,
    );

    expect(outcome.offsetSeconds, closeTo(0.13, 0.001));
    expect(outcome.hitCount, 12);
  });

  test('Too few hits fails rather than averaging a handful', () {
    final outcome = TapCalibration.measure(hitTimes: hits(0.13, count: 5), beatSeconds: beat);

    expect(outcome.failure, CalibrationFailure.tooFewHits);
    expect(outcome.offsetSeconds, isNull);
    expect(outcome.hitCount, 5);
  });

  test('Hits scattered around the beat fail as unsteady', () {
    final outcome = TapCalibration.measure(
      hitTimes: hits(0.13, wobble: [0.07, -0.07, 0.05, -0.06, 0.0, 0.075]),
      beatSeconds: beat,
    );

    expect(outcome.failure, CalibrationFailure.unsteady);
    expect(outcome.offsetSeconds, isNull);
  });

  test('Hits with no relation to the beat fail as unsteady', () {
    final outcome = TapCalibration.measure(
      hitTimes: [for (var i = 0; i < 20; i++) i * 0.37],
      beatSeconds: beat,
    );

    expect(outcome.failure, CalibrationFailure.unsteady);
  });
}
