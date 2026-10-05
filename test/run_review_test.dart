import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/run_review.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';

void main() {
  // Measure 1: quarter, quarter rest, two eighths, quarter. Measure 2 (3/4):
  // three quarters.
  final score = RhythmScore(
    title: 'Review',
    tempoBpm: 60,
    measures: [
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.eighth, EventType.normal),
        RhythmEvent(NoteValue.eighth, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.normal),
      ]),
      Measure(
        List.filled(3, const RhythmEvent(NoteValue.quarter, EventType.normal)),
        meter: const TimeSignature(3, 4),
      ),
    ],
  );

  test('The timeline layout knows where every note sits in the score', () {
    final layout = TimelineLayout(score);

    expect(layout.noteLocations, [(1, 1), (1, 2), (1, 3), (1, 4), (2, 1), (2, 2), (2, 3)]);
    expect(layout.labelFor(0), 'Count-in');
    expect(layout.labelFor(2), 'Measure 2');
    expect(layout.starts, [0, 48, 96, 132]);
    expect(layout.showsTimeSignature(0), isTrue);
    expect(layout.showsTimeSignature(1), isFalse, reason: 'same 4/4 as the count-in');
    expect(layout.showsTimeSignature(2), isTrue, reason: 'changes to 3/4');
  });

  RunReview reviewOf(List<JudgedHit> judgements) => RunReview(
        layout: TimelineLayout(score),
        secondsPerUnit: 1 / 12,
        noteTimes: [4.0, 6.0, 6.5, 7.0, 8.0, 9.0, 10.0],
        judgements: judgements,
        counts: const {},
        audio: Int16List(44100),
        sampleRate: 44100,
        timingEstimated: false,
      );

  test('mostOff lists the Greats and Goods furthest from their notes, worst first', () {
    final review = reviewOf(const [
      JudgedHit(Judgement.perfect, noteIndex: 0, offsetSeconds: 0.03),
      JudgedHit(Judgement.great, noteIndex: 1, offsetSeconds: -0.05),
      JudgedHit(Judgement.good, noteIndex: 2, offsetSeconds: 0.11),
      JudgedHit(Judgement.miss, noteIndex: 3),
      JudgedHit(Judgement.great, noteIndex: 4, offsetSeconds: 0.07),
      JudgedHit(Judgement.fail, hitTimeSeconds: 5.0),
      JudgedHit(Judgement.good, noteIndex: 5, offsetSeconds: -0.09),
    ]);

    expect(review.mostOff().map((hit) => hit.noteIndex), [2, 5, 4]);
    expect(review.mostOff(count: 10).length, 4, reason: 'no Perfects, Misses or Fails');
    expect(review.missedNotes.single.noteIndex, 3);
  });

  test('A judged note is located by measure and note number', () {
    final review = reviewOf(const []);

    expect(review.locate(const JudgedHit(Judgement.good, noteIndex: 2)), 'Measure 1, note 3');
    expect(review.locate(const JudgedHit(Judgement.good, noteIndex: 5)), 'Measure 2, note 2');
    expect(review.timelineMeasureOf(const JudgedHit(Judgement.good, noteIndex: 5)), 2);
  });
}
