import '../models/rhythm_score.dart';

/// One note under a beam.
class BeamedNote {
  /// Index into the measure's events.
  final int eventIndex;

  /// Where the note starts, in [RhythmGrid] units from the start of the
  /// measure.
  final int startUnits;

  /// How many beams the note carries: 1 for an eighth (or a triplet eighth),
  /// 2 for a sixteenth.
  final int beams;

  const BeamedNote(this.eventIndex, this.startUnits, this.beams);

  @override
  bool operator ==(Object other) =>
      other is BeamedNote &&
      other.eventIndex == eventIndex &&
      other.startUnits == startUnits &&
      other.beams == beams;

  @override
  int get hashCode => Object.hash(eventIndex, startUnits, beams);

  @override
  String toString() => 'BeamedNote($eventIndex, $startUnits, $beams)';
}

/// How many beams a note of [value] carries, or 0 for one that has no flag
/// to replace (a quarter or half note).
int beamCount(NoteValue value) {
  switch (value) {
    case NoteValue.half:
    case NoteValue.quarter:
    case NoteValue.quarterTriplet:
      return 0;
    case NoteValue.eighth:
    case NoteValue.eighthTriplet:
      return 1;
    case NoteValue.sixteenth:
    case NoteValue.sixteenthTriplet:
      return 2;
  }
}

/// The stretch of a measure one beam may cover: a quarter note, or -- in the
/// eighth-note meters counted in threes (3/8, 6/8, 9/8, 12/8) -- three
/// eighths, as printed music groups them.
int beamSpanUnits(TimeSignature meter) {
  final compound = meter.beatUnit == 8 && meter.beats % 3 == 0;
  return compound ? 3 * NoteValue.eighth.units : NoteValue.quarter.units;
}

/// The groups of notes in [measure] that are joined by a beam, in order.
///
/// Flagged notes (eighths, triplet eighths, sixteenths) next to each other
/// are joined. A rest or a longer note ends a group, and so does the end of
/// each [beamSpanUnits] stretch, so the beats stay readable. A flagged note
/// left on its own is in no group -- it keeps its flag.
List<List<BeamedNote>> beamGroups(Measure measure) {
  final spanUnits = beamSpanUnits(measure.meter);
  final groups = <List<BeamedNote>>[];
  var group = <BeamedNote>[];

  void endGroup() {
    if (group.length > 1) groups.add(group);
    group = [];
  }

  var startUnits = 0;
  for (final (index, event) in measure.events.indexed) {
    final beams = event.isRest ? 0 : beamCount(event.value);
    if (beams == 0) {
      endGroup();
    } else {
      if (group.isNotEmpty && group.first.startUnits ~/ spanUnits != startUnits ~/ spanUnits) {
        endGroup();
      }
      group.add(BeamedNote(index, startUnits, beams));
    }
    startUnits += event.durationUnits;
  }
  endGroup();
  return groups;
}
