import 'package:dart_midi_pro/dart_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/midi_score_codec.dart';

void main() {
  test('RhythmScore round-trips through MIDI bytes', () {
    var score = RhythmScore.empty(title: 'Test Rhythm', tempoBpm: 120);

    // Measure 1: accent quarter, normal eighth, normal eighth, eighth rest,
    // accent sixteenth, quarter rest, sixteenth rest
    // (12+6+6+6+3+12+3 = 48 units -- a complete measure).
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
    // A lone sixteenth note at the very start of a measure leaves a 45-unit
    // gap, which should decode as quarter+quarter+quarter+eighth+sixteenth
    // rests (12+12+12+6+3 = 45), the greedy largest-fit breakdown.
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

  test('Eighth-note triplets round-trip through MIDI bytes', () {
    var score = RhythmScore.empty(title: 'Triplets');

    // Beat 1: a full triplet. Beat 2: two triplet rests, then the last
    // triplet note -- an 8-unit gap that only two triplet rests can fill (an
    // eighth rest would strand 2 units). Beat 3: triplet note, then two
    // triplet rests. Beat 4: two eighths.
    const events = [
      RhythmEvent(NoteValue.eighthTriplet, EventType.accent),
      RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
      RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
      RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
      RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
      RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
      RhythmEvent(NoteValue.eighthTriplet, EventType.accent),
      RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
      RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
      RhythmEvent(NoteValue.eighth, EventType.normal),
      RhythmEvent(NoteValue.eighth, EventType.normal),
    ];
    var measure0 = Measure.empty();
    for (final event in events) {
      measure0 = measure0.appendEvent(event);
    }
    expect(measure0.isComplete, isTrue);
    score = score.copyWithMeasure(0, measure0);

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.measures[0], equals(measure0));
  });

  test('A lone triplet note decodes with its group and measure completed by rests', () {
    var score = RhythmScore.empty();
    score = score.copyWithMeasure(
      0,
      Measure.empty().appendEvent(const RhythmEvent(NoteValue.eighthTriplet, EventType.normal)),
    );

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(
      decoded.measures[0].events,
      equals(const [
        RhythmEvent(NoteValue.eighthTriplet, EventType.normal),
        RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
        RhythmEvent(NoteValue.eighthTriplet, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.rest),
      ]),
    );
  });

  test('A non-4/4 meter round-trips through MIDI bytes', () {
    const sevenFour = TimeSignature(7, 4);
    var score = RhythmScore.empty(title: 'Seven Four', meter: sevenFour);
    expect(sevenFour.units, equals(84));

    var measure0 = Measure.empty(meter: sevenFour);
    for (var i = 0; i < 7; i++) {
      measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    }
    score = score.copyWithMeasure(0, measure0);

    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);

    expect(decoded.measures.every((m) => m.meter == sevenFour), isTrue);
    expect(decoded.measures.length, 8);
    expect(decoded.measures[0], equals(measure0));
  });

  test('A half-note-beat meter (3/2) round-trips through MIDI bytes', () {
    const threeTwo = TimeSignature(3, 2);
    var score = RhythmScore.empty(title: 'Three Two', meter: threeTwo);
    // 3 beats * 24 units per half-note beat = 72.
    expect(threeTwo.units, equals(72));

    var measure0 = Measure.empty(meter: threeTwo);
    for (var i = 0; i < 6; i++) {
      measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    }
    score = score.copyWithMeasure(0, measure0);

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.measures[0].meter, threeTwo);
    expect(decoded.measures[0], equals(measure0));
  });

  test('Different time signatures in different measures round-trip through MIDI bytes', () {
    // 4/4, 4/4, 3/4, 3/4, 7/4, 3/2, 3/2, 4/4 -- each measure filled with
    // its own number of quarter notes.
    const meters = [
      TimeSignature(4, 4),
      TimeSignature(4, 4),
      TimeSignature(3, 4),
      TimeSignature(3, 4),
      TimeSignature(7, 4),
      TimeSignature(3, 2),
      TimeSignature(3, 2),
      TimeSignature(4, 4),
    ];
    final score = RhythmScore(
      title: 'Changing',
      tempoBpm: 100,
      measures: [
        for (final meter in meters)
          Measure(
            List.filled(
              meter.units ~/ NoteValue.quarter.units,
              const RhythmEvent(NoteValue.quarter, EventType.normal),
            ),
            meter: meter,
          ),
      ],
    );

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.measures.map((m) => m.meter), meters);
    expect(decoded.measures, equals(score.measures));
  });

  test('A file with a note-on ahead of the previous note-off on the same tick still reads right',
      () {
    // How files saved before the tie fix could come out: two eighth notes
    // back to back (240 ticks each), with the second note's note-on written
    // before the first one's note-off.
    MidiEvent at(int delta, MidiEvent event) => event..deltaTime = delta;
    NoteOnEvent on(int velocity) => NoteOnEvent()
      ..noteNumber = 38
      ..velocity = velocity
      ..channel = 9;
    NoteOffEvent off() => NoteOffEvent()
      ..noteNumber = 38
      ..velocity = 0
      ..channel = 9;
    final bytes = MidiWriter().writeMidiToBuffer(
      MidiFile(
        [
          [
            at(0, TrackNameEvent()..text = 'Old file'),
            at(0, SetTempoEvent()..microsecondsPerBeat = 600000),
            at(0, on(110)),
            at(240, on(64)), // second note starts...
            at(0, off()), // ...before the first one's note-off
            at(240, off()),
            at(1440, EndOfTrackEvent()), // rest of the 4/4 measure
          ],
        ],
        MidiHeader(format: 0, numTracks: 1, ticksPerBeat: 480),
      ),
    );

    final decoded = MidiScoreCodec.decode(bytes);

    expect(decoded.measures.single.events.take(2), const [
      RhythmEvent(NoteValue.eighth, EventType.accent),
      RhythmEvent(NoteValue.eighth, EventType.normal),
    ]);
  });

  test('A long, dense score round-trips note for note', () {
    // Regression: notes back to back put one note's note-off and the next
    // one's note-on on the same tick, and with enough events List.sort (not
    // stable) could put the note-on first -- which the decoder misreads.
    var measure = Measure.empty();
    for (var i = 0; i < 16; i++) {
      measure = measure.appendEvent(
        RhythmEvent(NoteValue.sixteenth, i.isEven ? EventType.accent : EventType.normal),
      );
    }
    final score = RhythmScore(
      title: 'Sixteenths',
      tempoBpm: 100,
      measures: List.filled(8, measure),
    );

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.measures, equals(score.measures));
  });

  test('Instrument round-trips through MIDI bytes', () {
    var score = RhythmScore.empty(title: 'Kick Test', instrument: Instrument.kick);
    var measure0 = Measure.empty();
    measure0 = measure0.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.accent));
    score = score.copyWithMeasure(0, measure0);

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.instrument, equals(Instrument.kick));
  });

  test('Empty score defaults to the snare instrument on decode', () {
    final score = RhythmScore.empty(title: 'No Notes');
    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.instrument, equals(Instrument.snare));
  });

  test('A score grown beyond the starting 8 measures round-trips its full length', () {
    var score = RhythmScore.empty(title: 'Long Piece', measuresCount: 8);
    for (var i = 0; i < 3; i++) {
      score = score.appendMeasure();
    }
    expect(score.measures.length, equals(11));

    var lastMeasure = Measure.empty();
    lastMeasure = lastMeasure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.accent));
    score = score.copyWithMeasure(10, lastMeasure);

    final decoded = MidiScoreCodec.decode(MidiScoreCodec.encode(score));

    expect(decoded.measures.length, equals(11));
    expect(decoded.measures[10].events.first, equals(lastMeasure.events.first));
  });
}
