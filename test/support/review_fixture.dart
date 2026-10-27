import 'dart:typed_data';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/run_review.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';

/// A finished run to save, review or list: 60 BPM, one measure of four
/// quarter notes (due at 4-7s after a 4s count-in), played Perfect, Great+,
/// Good- and missed, with a hit in no rest at all.
RunReview sampleReview({
  String title = 'Groove',
  List<JudgedHit>? judgements,
  TempoBeat tempoBeat = TempoBeat.quarter,
}) {
  var measure = Measure.empty();
  for (var i = 0; i < 4; i++) {
    measure = measure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
  }
  final score = RhythmScore(title: title, tempoBpm: 60, tempoBeat: tempoBeat, measures: [measure]);
  final judged =
      judgements ??
      const [
        JudgedHit(Judgement.perfect, noteIndex: 0, offsetSeconds: 0.01, hitTimeSeconds: 4.01),
        JudgedHit(Judgement.great, noteIndex: 1, offsetSeconds: 0.06, hitTimeSeconds: 5.06),
        JudgedHit(Judgement.good, noteIndex: 2, offsetSeconds: -0.1, hitTimeSeconds: 5.9),
        JudgedHit(Judgement.miss, noteIndex: 3),
      ];
  final counts = {for (final judgement in Judgement.values) judgement: 0};
  for (final hit in judged) {
    counts[hit.judgement] = counts[hit.judgement]! + 1;
  }
  return RunReview(
    layout: TimelineLayout(score),
    secondsPerUnit: 1 / 12,
    noteTimes: const [4.0, 5.0, 6.0, 7.0],
    judgements: judged,
    counts: counts,
    audio: Int16List.fromList([for (var i = 0; i < 44100 * 9; i++) (i % 200) - 100]),
    sampleRate: 44100,
    timingEstimated: false,
  );
}
