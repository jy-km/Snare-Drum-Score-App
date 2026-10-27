import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/widgets/beam_groups.dart';

const _quarter = NoteValue.quarter;
const _eighth = NoteValue.eighth;
const _sixteenth = NoteValue.sixteenth;
const _triplet = NoteValue.eighthTriplet;

RhythmEvent _note(NoteValue value) => RhythmEvent(value, EventType.normal);
RhythmEvent _rest(NoteValue value) => RhythmEvent(value, EventType.rest);

/// Each group as the indices of its notes.
List<List<int>> _indices(Measure measure) => [
  for (final group in beamGroups(measure)) [for (final note in group) note.eventIndex],
];

void main() {
  test('Two eighth notes next to each other are joined', () {
    final measure = Measure([_note(_eighth), _note(_eighth)]);

    expect(beamGroups(measure), [
      [const BeamedNote(0, 0, 1), const BeamedNote(1, 6, 1)],
    ]);
  });

  test('Four sixteenths are joined, with two beams each', () {
    final measure = Measure(List.filled(4, _note(_sixteenth)));

    final groups = beamGroups(measure);
    expect(groups, hasLength(1));
    expect(groups.single.map((note) => note.beams), [2, 2, 2, 2]);
    expect(groups.single.map((note) => note.startUnits), [0, 3, 6, 9]);
  });

  test('A beam ends at each beat', () {
    final measure = Measure(List.filled(8, _note(_eighth)));

    expect(_indices(measure), [
      [0, 1],
      [2, 3],
      [4, 5],
      [6, 7],
    ]);
  });

  test('Eighths and sixteenths in one beat share a beam', () {
    final measure = Measure([_note(_eighth), _note(_sixteenth), _note(_sixteenth)]);

    final groups = beamGroups(measure);
    expect(groups.single.map((note) => note.beams), [1, 2, 2]);
  });

  test('A rest ends a beam', () {
    final measure = Measure([
      _note(_sixteenth),
      _note(_sixteenth),
      _rest(_sixteenth),
      _note(_sixteenth),
    ]);

    expect(_indices(measure), [
      [0, 1],
    ]);
  });

  test('A note on its own keeps its flag', () {
    final measure = Measure([
      _note(_eighth),
      _rest(_eighth),
      _note(_quarter),
      _note(_eighth),
      _note(_quarter),
    ]);

    expect(beamGroups(measure), isEmpty);
  });

  test('Quarter and half notes are never under a beam', () {
    final measure = Measure([_note(_quarter), _note(NoteValue.half), _note(_quarter)]);

    expect(beamGroups(measure), isEmpty);
  });

  test('A triplet is joined as one group', () {
    final measure = Measure([
      ...List.filled(3, _note(_triplet)),
      ...List.filled(3, _note(_triplet)),
    ]);

    expect(_indices(measure), [
      [0, 1, 2],
      [3, 4, 5],
    ]);
  });

  test('Notes off the beat are grouped by the beat they start in', () {
    // An eighth rest pushes the eighths off the beat: the first stands alone
    // at the end of beat 1, the next two straddle beats 2 and 3.
    final measure = Measure([
      _rest(_eighth),
      _note(_eighth),
      _note(_eighth),
      _note(_eighth),
      _note(_eighth),
    ]);

    expect(_indices(measure), [
      [2, 3],
    ]);
  });

  test('6/8 is beamed in threes', () {
    final measure = Measure(List.filled(6, _note(_eighth)), meter: const TimeSignature(6, 8));

    expect(_indices(measure), [
      [0, 1, 2],
      [3, 4, 5],
    ]);
  });

  test('7/8 is beamed in twos, with the odd eighth left over', () {
    final measure = Measure(List.filled(7, _note(_eighth)), meter: const TimeSignature(7, 8));

    expect(_indices(measure), [
      [0, 1],
      [2, 3],
      [4, 5],
    ]);
  });

  test('A half-note beat (2/2) is still beamed by the quarter note', () {
    final measure = Measure(List.filled(8, _note(_eighth)), meter: const TimeSignature(2, 2));

    expect(_indices(measure), hasLength(4));
  });

  test('Sixteenth-note triplets share a double beam; quarter-note triplets have none', () {
    const st = RhythmEvent(NoteValue.sixteenthTriplet, EventType.normal);
    const qt = RhythmEvent(NoteValue.quarterTriplet, EventType.normal);
    final measure = Measure(const [st, st, st, st, st, st, qt, qt, qt, st, st, st]);

    final groups = beamGroups(measure);

    expect(groups, hasLength(2));
    expect(groups[0].map((note) => note.eventIndex), [0, 1, 2, 3, 4, 5]);
    expect(groups[0].every((note) => note.beams == 2), isTrue);
    expect(groups[1].map((note) => note.eventIndex), [9, 10, 11]);
  });
}
