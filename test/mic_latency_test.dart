import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/mic_latency.dart';

void main() {
  test('An empty history has no typical delay and is not reliable', () {
    final history = MicLatencyHistory();

    expect(history.typical, isNull);
    expect(history.isReliable, isFalse);
  });

  test('Becomes reliable at three measurements', () {
    var history = MicLatencyHistory().adding(0.12).adding(0.13);
    expect(history.isReliable, isFalse);

    history = history.adding(0.11);
    expect(history.isReliable, isTrue);
  });

  test('The typical delay is the median, so one odd run does not move it', () {
    final history = MicLatencyHistory([0.12, 0.45, 0.11, 0.13, 0.12]);

    expect(history.typical, 0.12);
  });

  test('Only the most recent measurements are kept', () {
    var history = MicLatencyHistory();
    for (var i = 0; i < 12; i++) {
      history = history.adding(i / 100);
    }

    expect(history.measurements.length, 9);
    expect(history.measurements.first, 0.03);
    expect(history.measurements.last, 0.11);
  });
}
