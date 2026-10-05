import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';

void main() {
  test('noteStartUnits lists where each note starts, skipping rests, across measures', () {
    var score = RhythmScore.empty(measuresCount: 2);
    // Measure 1: quarter note, eighth rest, eighth note, triplet x3.
    score = score.copyWithMeasure(
      0,
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.eighth, EventType.rest),
        RhythmEvent(NoteValue.eighth, EventType.accent),
        RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
        RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
        RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
      ]),
    );
    // Measure 2: quarter rest, then a quarter note.
    score = score.copyWithMeasure(
      1,
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.normal),
      ]),
    );

    expect(score.noteStartUnits, [0, 18, 24, 28, 32, 48 + 12]);
  });

  group('withMeterFrom', () {
    const threeFour = TimeSignature(3, 4);
    Measure quarters(int count, {TimeSignature meter = TimeSignature.common}) => Measure(
          List.filled(count, const RhythmEvent(NoteValue.quarter, EventType.normal)),
          meter: meter,
        );

    test('changes the chosen measure and every later empty one, never earlier ones', () {
      final score = RhythmScore.empty(measuresCount: 5).withMeterFrom(2, threeFour);

      expect(score.measures.map((m) => m.meter.toString()), ['4/4', '4/4', '3/4', '3/4', '3/4']);
    });

    test('leaves a later measure that has notes exactly as it was', () {
      final withNotes = quarters(2);
      final score = RhythmScore.empty(measuresCount: 4)
          .copyWithMeasure(2, withNotes)
          .withMeterFrom(0, threeFour);

      expect(score.measures[2], equals(withNotes));
      // ...but later empty measures still change.
      expect(score.measures.map((m) => m.meter.toString()), ['3/4', '3/4', '4/4', '3/4']);
    });

    test('treats a later measure of only rests as empty', () {
      final restsOnly = Measure(const [RhythmEvent(NoteValue.quarter, EventType.rest)]);
      final score = RhythmScore.empty(measuresCount: 2)
          .copyWithMeasure(1, restsOnly)
          .withMeterFrom(0, threeFour);

      expect(score.measures[1], equals(Measure.empty(meter: threeFour)));
    });

    test('keeps what fits of the chosen measure, from the start', () {
      final score = RhythmScore.empty(measuresCount: 1)
          .copyWithMeasure(0, quarters(4))
          .withMeterFrom(0, threeFour);

      expect(score.measures[0], equals(quarters(3, meter: threeFour)));
    });
  });

  test('Measure positions follow each measure\'s own length', () {
    final score = RhythmScore(
      title: 'Mixed',
      tempoBpm: 100,
      measures: [
        Measure(const [RhythmEvent(NoteValue.quarter, EventType.normal)]), // 4/4: 48
        Measure(
          const [RhythmEvent(NoteValue.quarter, EventType.normal)],
          meter: const TimeSignature(3, 4), // 36
        ),
        Measure.empty(meter: const TimeSignature(3, 2)), // 72
      ],
    );

    expect(score.measureStartUnits, [0, 48, 84, 156]);
    expect(score.totalUnits, 156);
    expect(score.noteStartUnits, [0, 48]);
    expect(score.restSpanUnits, [(12, 48), (60, 156)]);
    expect(score.measureIndexAt(47.9), 0);
    expect(score.measureIndexAt(48), 1);
    expect(score.measureIndexAt(100), 2);
    expect(score.measureIndexAt(500), 2);
  });

  test('noteStartUnits is empty for a score with no notes', () {
    expect(RhythmScore.empty().noteStartUnits, isEmpty);
  });

  test('restSpanUnits covers every rest and every unfilled end of a measure', () {
    var score = RhythmScore.empty(measuresCount: 3);
    // Measure 1: quarter note, eighth rest, eighth note, quarter rest,
    // quarter rest -- the two quarter rests run together, to the barline.
    score = score.copyWithMeasure(
      0,
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.eighth, EventType.rest),
        RhythmEvent(NoteValue.eighth, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
      ]),
    );
    // Measure 2: just one quarter note; the rest of it is left unfilled.
    score = score.copyWithMeasure(
      1,
      Measure(const [RhythmEvent(NoteValue.quarter, EventType.accent)]),
    );
    // Measure 3: empty.

    expect(score.restSpanUnits, [
      (12, 18),
      // Measure 1's closing rests, as one stretch; it stops at the barline
      // because measure 2 starts with a note.
      (24, 48),
      // Measure 2's unfilled end and all of the empty measure 3 together.
      (60, 144),
    ]);
  });

  test('restSpanUnits is empty for a score with no rests and no gaps', () {
    var measure = Measure.empty();
    for (var i = 0; i < 4; i++) {
      measure = measure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    }
    final score = RhythmScore.empty(measuresCount: 1).copyWithMeasure(0, measure);

    expect(score.restSpanUnits, isEmpty);
  });
}
