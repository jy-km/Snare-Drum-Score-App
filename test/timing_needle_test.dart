import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/widgets/timing_needle.dart';

void main() {
  test('On time is the middle; the Good window reaches the edges, and beyond stays there', () {
    expect(TimingNeedle.positionOf(0), 0.5);
    expect(TimingNeedle.positionOf(-0.12), closeTo(0, 1e-9));
    expect(TimingNeedle.positionOf(0.12), closeTo(1, 1e-9));
    expect(TimingNeedle.positionOf(0.06), closeTo(0.75, 1e-9));
    expect(TimingNeedle.positionOf(-0.5), 0);
    expect(TimingNeedle.positionOf(0.5), 1);
  });

  test('Shows the latest hits on notes only, oldest first', () {
    final judgements = [
      for (var i = 0; i < 10; i++)
        JudgedHit(
          Judgement.perfect,
          noteIndex: i,
          offsetSeconds: i / 1000,
          hitTimeSeconds: i + 0.0,
        ),
      const JudgedHit(Judgement.miss, noteIndex: 10),
      const JudgedHit(Judgement.fail, hitTimeSeconds: 11.5),
    ];

    final recent = TimingNeedle.recent(judgements);

    expect(recent, hasLength(TimingNeedle.trailLength));
    expect([for (final hit in recent) hit.noteIndex], [2, 3, 4, 5, 6, 7, 8, 9]);
  });
}
