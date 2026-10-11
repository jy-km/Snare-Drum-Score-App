import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/widgets/beat_count.dart';

void main() {
  Measure filledWith(List<NoteValue> values, {TimeSignature meter = TimeSignature.common}) {
    var measure = Measure.empty(meter: meter);
    for (final value in values) {
      measure = measure.appendEvent(RhythmEvent(value, EventType.normal));
    }
    return measure;
  }

  test('Whole beats', () {
    expect(filledBeatsText(Measure.empty()), '0 of 4 beats filled');
    expect(filledBeatsText(filledWith([NoteValue.quarter, NoteValue.quarter])), '2 of 4 beats filled');
  });

  test('Part of a beat is a fraction', () {
    expect(filledBeatsText(filledWith([NoteValue.eighth])), '½ of 4 beats filled');
    expect(filledBeatsText(filledWith([NoteValue.quarter, NoteValue.sixteenth])),
        '1¼ of 4 beats filled');
    expect(filledBeatsText(filledWith([NoteValue.eighthTriplet, NoteValue.eighthTriplet])),
        '⅔ of 4 beats filled');
    expect(
      filledBeatsText(filledWith([NoteValue.quarter, NoteValue.sixteenth, NoteValue.eighthTriplet])),
      '1 7/12 of 4 beats filled',
      reason: 'no single character for twelfths',
    );
  });

  test('Counts in the measure\'s own beat: half notes in x/2, eighths in x/8', () {
    expect(
      filledBeatsText(filledWith([NoteValue.quarter], meter: const TimeSignature(3, 2))),
      '½ of 3 beats filled',
    );
    expect(
      filledBeatsText(filledWith([NoteValue.quarter, NoteValue.sixteenth],
          meter: const TimeSignature(7, 8))),
      '2½ of 7 beats filled',
    );
  });

  test('One beat is a "beat"', () {
    expect(filledBeatsText(Measure.empty(meter: const TimeSignature(1, 4))), '0 of 1 beat filled');
  });
}
