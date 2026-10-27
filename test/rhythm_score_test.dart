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

  group('Editing inside a measure', () {
    final measure = Measure(const [
      RhythmEvent(NoteValue.quarter, EventType.normal),
      RhythmEvent(NoteValue.eighth, EventType.accent),
      RhythmEvent(NoteValue.quarter, EventType.rest),
    ]); // 2.5 of 4 beats

    test('replaceAt swaps one event, keeping the rest in order', () {
      expect(
        measure.replaceAt(1, const RhythmEvent(NoteValue.quarter, EventType.normal)).events,
        const [
          RhythmEvent(NoteValue.quarter, EventType.normal),
          RhythmEvent(NoteValue.quarter, EventType.normal),
          RhythmEvent(NoteValue.quarter, EventType.rest),
        ],
      );
    });

    test('canReplace allows only what still fits', () {
      expect(measure.canReplace(1, NoteValue.quarter), isTrue); // 3 beats
      final full = measure
          .appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal))
          .removeLast()
          .appendEvent(const RhythmEvent(NoteValue.eighth, EventType.normal))
          .appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal)); // 4 beats
      expect(full.canReplace(1, NoteValue.quarter), isFalse);
      expect(full.canReplace(1, NoteValue.sixteenth), isTrue);
    });

    test('removeAt drops one event and closes the gap', () {
      expect(measure.removeAt(0).events, const [
        RhythmEvent(NoteValue.eighth, EventType.accent),
        RhythmEvent(NoteValue.quarter, EventType.rest),
      ]);
      expect(measure.removeAt(0).meter, measure.meter);
    });
  });

  test('removeMeasure drops one measure; the ones after move up', () {
    final second = Measure(const [RhythmEvent(NoteValue.quarter, EventType.normal)]);
    final score = RhythmScore.empty(measuresCount: 3).copyWithMeasure(1, second);

    final removed = score.removeMeasure(0);

    expect(removed.measures.length, 2);
    expect(removed.measures.first, second);
  });

  test('Eighth-note meters: a beat is an eighth note', () {
    const sixEight = TimeSignature(6, 8);
    expect(sixEight.isValid, isTrue);
    expect(sixEight.unitsPerBeat, NoteValue.eighth.units);
    expect(sixEight.units, 36); // same length as 3/4
    expect(const TimeSignature(16, 8).isValid, isTrue);
    expect(const TimeSignature(17, 8).isValid, isFalse);
    expect(const TimeSignature(4, 16).isValid, isFalse, reason: 'sixteenths not offered');
  });

  test('A flam or drag belongs to a note: a rest never has one', () {
    const flam = RhythmEvent(NoteValue.quarter, EventType.normal, ornament: Ornament.flam);
    expect(flam.ornament, Ornament.flam);
    expect(flam, isNot(equals(const RhythmEvent(NoteValue.quarter, EventType.normal))));
    expect(flam.durationUnits, NoteValue.quarter.units, reason: 'grace notes take no time');

    const rest = RhythmEvent(NoteValue.quarter, EventType.rest, ornament: Ornament.drag);
    expect(rest.ornament, Ornament.none);

    expect(Ornament.flam.graceNoteCount, 1);
    expect(Ornament.drag.graceNoteCount, 2);
  });

  test('A marcato is louder than an accent', () {
    expect(EventType.marcato.velocity, greaterThan(EventType.accent.velocity));
  });

  test('A roll is still one note of its own length, as far as judging goes', () {
    final plain = RhythmScore.empty(measuresCount: 1).copyWithMeasure(
      0,
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.half, EventType.normal),
      ]),
    );
    final rolled = plain.copyWithMeasure(
      0,
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal, ornament: Ornament.roll),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.half, EventType.normal, ornament: Ornament.roll),
      ]),
    );

    expect(rolled.noteStartUnits, plain.noteStartUnits);
    expect(rolled.restSpanUnits, plain.restSpanUnits);
    expect(Ornament.roll.graceNoteCount, 0);
  });

  test('Notes with grace strokes are counted among the notes, skipping rests', () {
    final score = RhythmScore.empty(measuresCount: 2)
        .copyWithMeasure(
          0,
          Measure(const [
            RhythmEvent(NoteValue.quarter, EventType.normal),
            RhythmEvent(NoteValue.quarter, EventType.rest),
            RhythmEvent(NoteValue.quarter, EventType.normal, ornament: Ornament.flam),
            RhythmEvent(NoteValue.quarter, EventType.normal, ornament: Ornament.roll),
          ]),
        )
        .copyWithMeasure(
          1,
          Measure(const [RhythmEvent(NoteValue.half, EventType.accent, ornament: Ornament.drag)]),
        );

    expect(score.graceNoteIndexes, {1, 3});
  });

  test('Three triplet notes span the next longer plain note', () {
    expect(NoteValue.quarterTriplet.units * 3, NoteValue.half.units);
    expect(NoteValue.eighthTriplet.units * 3, NoteValue.quarter.units);
    expect(NoteValue.sixteenthTriplet.units * 3, NoteValue.eighth.units);
    expect(NoteValue.values.where((value) => value.isTriplet), hasLength(3));
  });

  group('Tempo beat', () {
    test('150 BPM in half notes is 300 quarter notes a minute', () {
      expect(TempoBeat.half.msPerUnit(150), closeTo(TempoBeat.quarter.msPerUnit(300), 1e-9));
      expect(TempoBeat.eighth.msPerUnit(150), closeTo(TempoBeat.quarter.msPerUnit(75), 1e-9));
      expect(TempoBeat.quarter.convert(150, TempoBeat.half), 300);
      expect(TempoBeat.half.convert(150, TempoBeat.eighth), 37.5);
    });

    test('a dotted quarter is a quarter and a half: 60 of them a minute is 90 quarter notes', () {
      expect(TempoBeat.dottedQuarter.units, NoteValue.quarter.units * 3 ~/ 2);
      expect(TempoBeat.quarter.convert(60, TempoBeat.dottedQuarter), 90);
      expect(TempoBeat.dottedQuarter.describe(60), '60 BPM (1/4.)');
    });

    test('a quarter note at 60 BPM lasts a second', () {
      expect(TempoBeat.quarter.msPerUnit(60) * NoteValue.quarter.units, closeTo(1000, 1e-9));
    });

    test('is written out unless it is the usual quarter note', () {
      expect(TempoBeat.quarter.describe(120), '120 BPM');
      expect(TempoBeat.half.describe(150), '150 BPM (1/2)');
      expect(TempoBeat.eighth.describe(200), '200 BPM (1/8)');
    });

    test('defaults to the quarter note and takes part in equality', () {
      final score = RhythmScore.empty();
      expect(score.tempoBeat, TempoBeat.quarter);
      final half = score.copyWith(tempoBeat: TempoBeat.half);
      expect(half.tempoBeat, TempoBeat.half);
      expect(half, isNot(score));
      expect(half.copyWith(tempoBpm: 90).tempoBeat, TempoBeat.half);
    });
  });
}
