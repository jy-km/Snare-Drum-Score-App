import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/midi_score_codec.dart';

void main() {
  test('RhythmScore round-trips through MIDI bytes', () {
    var score = RhythmScore.empty(title: 'Test Rhythm', tempoBpm: 120);

    // Measure 1: accent quarter, normal eighth, normal eighth, eighth rest,
    // accent sixteenth, quarter rest, sixteenth rest
    // (4+2+2+2+1+4+1 = 16 units -- a complete measure).
    // Rests aren't encoded as MIDI events at all -- only a gap's total
    // silent duration survives the
    // round-trip, reconstructed using the largest-fitting rest tokens first.
    // For an *incomplete* measure, any trailing silence also gets filled in
    // as rests on decode (there's no way to distinguish "intentionally left
    // incomplete" from "trailing rests" once it's just MIDI silence), so
    // only a fully-complete measure -- with any rest gaps already in
    // largest-fit form -- round-trips to an identical event list.
    var measure0 = Measure.empty();
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.accent));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.eighth, EventType.normal));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.eighth, EventType.normal));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.eighth, EventType.rest));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.sixteenth, EventType.accent));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.rest));
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.sixteenth, EventType.rest));
    expect(measure0.isComplete, isTrue);
    score = score.copyWithMeasure(0, measure0);

    // Measure 8: four quarter notes, exactly filling the measure.
    var measure7 = Measure.empty();
    measure7 = measure7.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    measure7 = measure7.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.accent));
    measure7 = measure7.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    measure7 = measure7.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    score = score.copyWithMeasure(7, measure7);

    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);

    // Both measures are complete, with rests already in largest-fit form,
    // so both round-trip to an identical event list.
    expect(decoded.measures[0], equals(measure0));
    expect(decoded.measures[7], equals(measure7));
    expect(decoded.title, equals(score.title));
    expect(decoded.tempoBpm, equals(score.tempoBpm));
  });

  test('Empty score round-trips to all-rest measures', () {
    final score = RhythmScore.empty(title: 'Silence', tempoBpm: 80);
    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);

    for (final measure in decoded.measures) {
      expect(measure.isComplete, isTrue);
      expect(measure.events.every((e) => e.isRest), isTrue);
    }
    expect(decoded.tempoBpm, equals(80));
  });

  test('A gap decodes to the largest-fitting rest values', () {
    // A lone sixteenth note at the very start of a measure leaves a 15-unit
    // gap, which should decode as quarter+quarter+quarter+eighth+sixteenth
    // rests (4+4+4+2+1 = 15), the greedy largest-fit breakdown.
    var score = RhythmScore.empty();
    var measure0 = Measure.empty();
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.sixteenth, EventType.normal));
    score = score.copyWithMeasure(0, measure0);

    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);

    final restsAfterNote = decoded.measures[0].events.skip(1).toList();
    expect(
      restsAfterNote,
      equals(const [
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.eighth, EventType.rest),
        RhythmEvent(NoteValue.sixteenth, EventType.rest),
      ]),
    );
  });
}
