import '../models/rhythm_score.dart';

/// How a practice run lays a score out in time: a count-in measure, then
/// the score's measures, one after another on a single timeline measured in
/// [RhythmGrid] units from the start of the count-in. Timeline measure 0 is
/// the count-in; timeline measure `n` is the score's measure `n` (1-based).
///
/// Shared by the practice screen (which plays the run) and the review
/// screen (which replays it), so both place everything identically.
class TimelineLayout {
  final RhythmScore score;

  TimelineLayout(this.score);

  /// The count-in is in the first measure's time signature (one click per
  /// beat), so it leads into Measure 1 the way a conductor would.
  TimeSignature get countInMeter => score.measures.first.meter;

  /// Visual stand-in for the count-in: there's no "half note" [NoteValue],
  /// so a half-note beat is shown as 2 back-to-back quarter notes per beat
  /// instead of inventing a new note value just for this.
  late final Measure countInMeasure = Measure(
    List.generate(
      countInMeter.beats * (countInMeter.unitsPerBeat ~/ NoteValue.quarter.units),
      (_) => const RhythmEvent(NoteValue.quarter, EventType.normal),
    ),
    meter: countInMeter,
  );

  /// The count-in plus the score's measures.
  int get measureCount => score.measures.length + 1;

  /// Where each timeline measure starts, in units, with one more entry at
  /// the end where the timeline ends. Measures can each have their own time
  /// signature, so they aren't evenly spaced.
  late final List<int> starts = [
    0,
    for (final start in score.measureStartUnits) countInMeter.units + start,
  ];

  int get totalUnits => starts.last;

  /// Which timeline measure [units] falls in.
  int indexAt(double units) {
    for (var index = 0; index < measureCount; index++) {
      if (units < starts[index + 1]) return index;
    }
    return measureCount - 1;
  }

  Measure measureAt(int index) => index == 0 ? countInMeasure : score.measures[index - 1];

  String labelFor(int index) => index == 0 ? 'Count-in' : 'Measure $index';

  /// Whether timeline measure [index] should print its time signature: the
  /// count-in does, and so does any measure whose meter differs from the
  /// one before it.
  bool showsTimeSignature(int index) =>
      index == 0 || measureAt(index).meter != measureAt(index - 1).meter;

  /// For each of the score's notes, in playing order (the same order as
  /// [RhythmScore.noteStartUnits]): which measure it's in (1-based) and
  /// which note of that measure it is (1-based).
  late final List<(int, int)> noteLocations = [
    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++)
      for (var noteNumber = 1;
          noteNumber <= score.measures[measureIndex].events.where((e) => !e.isRest).length;
          noteNumber++)
        (measureIndex + 1, noteNumber),
  ];
}
