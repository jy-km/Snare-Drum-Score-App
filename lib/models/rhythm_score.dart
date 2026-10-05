import 'package:flutter/foundation.dart';

/// Grid dimensions. Every duration and position is an integer count of
/// "units", where one unit is 1/[unitsPerQuarterNote] of a quarter note --
/// the coarsest resolution at which both a sixteenth note (3 units) and an
/// eighth-note triplet (4 units) are whole numbers. The time signature is
/// per-measure (see [TimeSignature]) -- numerator within
/// [minBeatsPerMeasure]..[maxBeatsPerMeasureFor], denominator one of
/// [beatUnits] (quarter-note or half-note beats). The number of measures is
/// also per-score and growable (see
/// [RhythmScore.appendMeasure]); [defaultMeasuresCount] is only the starting
/// count for a newly created score.
class RhythmGrid {
  static const int defaultMeasuresCount = 8;
  static const int unitsPerQuarterNote = 12;
  static const int defaultBeatsPerMeasure = 4;
  static const int minBeatsPerMeasure = 1;
  static const int maxBeatsPerMeasure = 16;

  /// Units in a whole note -- 4 quarter notes.
  static const int unitsPerWholeNote = 4 * unitsPerQuarterNote;

  /// Valid time-signature denominators: a quarter-note beat (4, the
  /// original/default) or a half-note beat (2).
  static const List<int> beatUnits = [4, 2];
  static const int defaultBeatUnit = 4;

  /// The numerator's upper bound depends on the denominator: 1/4..16/4 for a
  /// quarter-note beat, 1/2..8/2 for a half-note beat.
  static int maxBeatsPerMeasureFor(int beatUnit) => beatUnit == 2 ? 8 : maxBeatsPerMeasure;

  /// Units for a measure at [defaultBeatsPerMeasure]/[defaultBeatUnit] (4/4).
  static const int defaultUnitsPerMeasure = defaultBeatsPerMeasure * unitsPerQuarterNote;
}

/// A measure's time signature: [beats] beats of a [beatUnit] note each
/// (4 = quarter note, 2 = half note).
@immutable
class TimeSignature {
  final int beats;
  final int beatUnit;

  const TimeSignature(this.beats, this.beatUnit);

  /// 4/4.
  static const common =
      TimeSignature(RhythmGrid.defaultBeatsPerMeasure, RhythmGrid.defaultBeatUnit);

  /// A measure's capacity in [RhythmGrid] units under this time signature.
  int get units => beats * unitsPerBeat;

  int get unitsPerBeat => RhythmGrid.unitsPerWholeNote ~/ beatUnit;

  bool get isValid =>
      RhythmGrid.beatUnits.contains(beatUnit) &&
      beats >= RhythmGrid.minBeatsPerMeasure &&
      beats <= RhythmGrid.maxBeatsPerMeasureFor(beatUnit);

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && other.beats == beats && other.beatUnit == beatUnit;

  @override
  int get hashCode => Object.hash(beats, beatUnit);

  @override
  String toString() => '$beats/$beatUnit';
}

/// Which drum sounds when a note is hit. Chosen per-score -- affects both
/// verification/practice
/// playback (see `ClickSound`) and which General MIDI percussion note the
/// score is encoded with.
enum Instrument { kick, snare, tambourine }

extension InstrumentMidiNote on Instrument {
  /// General MIDI percussion note number (channel 10) for this instrument.
  int get midiNoteNumber {
    switch (this) {
      case Instrument.kick:
        return 36; // Acoustic Bass Drum
      case Instrument.snare:
        return 38; // Acoustic Snare
      case Instrument.tambourine:
        return 54; // Tambourine
    }
  }

  static Instrument fromMidiNoteNumber(int noteNumber) {
    for (final instrument in Instrument.values) {
      if (instrument.midiNoteNumber == noteNumber) return instrument;
    }
    return Instrument.snare;
  }
}

/// [eighthTriplet] is one note of an eighth-note triplet: three of them span
/// one quarter note.
enum NoteValue { quarter, eighth, eighthTriplet, sixteenth }

extension NoteValueUnits on NoteValue {
  /// Duration in [RhythmGrid] units (out of a measure's capacity, which
  /// depends on the score's meter).
  int get units {
    switch (this) {
      case NoteValue.quarter:
        return 12;
      case NoteValue.eighth:
        return 6;
      case NoteValue.eighthTriplet:
        return 4;
      case NoteValue.sixteenth:
        return 3;
    }
  }
}

enum EventType { rest, normal, accent }

extension EventTypeVelocity on EventType {
  /// MIDI velocity (0-127) representing this type's dynamic.
  int get velocity {
    switch (this) {
      case EventType.rest:
        return 0;
      case EventType.normal:
        return 64;
      case EventType.accent:
        return 110;
    }
  }
}

/// One rhythmic token: a note or rest of a given [value] (duration).
class RhythmEvent {
  final NoteValue value;
  final EventType type;

  const RhythmEvent(this.value, this.type);

  int get durationUnits => value.units;

  bool get isRest => type == EventType.rest;

  int get velocity => type.velocity;

  @override
  bool operator ==(Object other) =>
      other is RhythmEvent && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);
}

/// A measure built by appending [RhythmEvent]s left to right (append-only
/// entry for v1), in its own time signature ([meter]). Always filled to at
/// most the meter's capacity (in [RhythmGrid] units); never overfilled.
class Measure {
  final List<RhythmEvent> events;
  final TimeSignature meter;

  Measure(this.events, {this.meter = TimeSignature.common}) : assert(meter.isValid);

  factory Measure.empty({TimeSignature meter = TimeSignature.common}) =>
      Measure(const [], meter: meter);

  static int _totalUnits(List<RhythmEvent> events) =>
      events.fold(0, (sum, e) => sum + e.durationUnits);

  /// This measure's capacity in [RhythmGrid] units.
  int get capacityUnits => meter.units;

  int get filledUnits => _totalUnits(events);

  int get remainingUnits => capacityUnits - filledUnits;

  bool get isComplete => remainingUnits == 0;

  /// Whether anything is to be played here -- a measure of only rests (or
  /// nothing) has no notes.
  bool get hasNotes => events.any((event) => !event.isRest);

  bool canAppend(NoteValue value) => value.units <= remainingUnits;

  Measure appendEvent(RhythmEvent event) {
    assert(canAppend(event.value));
    return Measure([...events, event], meter: meter);
  }

  Measure removeLast() {
    if (events.isEmpty) return this;
    return Measure(events.sublist(0, events.length - 1), meter: meter);
  }

  /// This measure in [meter] instead, keeping as many of its events, from
  /// the start, as fit the new capacity.
  Measure withMeter(TimeSignature meter) {
    final kept = <RhythmEvent>[];
    var filled = 0;
    for (final event in events) {
      if (filled + event.durationUnits > meter.units) break;
      kept.add(event);
      filled += event.durationUnits;
    }
    return Measure(kept, meter: meter);
  }

  @override
  bool operator ==(Object other) =>
      other is Measure && other.meter == meter && listEquals(other.events, events);

  @override
  int get hashCode => Object.hash(meter, Object.hashAll(events));
}

class RhythmScore {
  final String title;

  /// The target tempo the piece is meant to be played at (BPM). Distinct
  /// from a future, independently adjustable practice-session tempo.
  final int tempoBpm;

  /// Which drum sounds for every hit in this score.
  final Instrument instrument;

  /// Each with its own time signature (see [Measure.meter]).
  final List<Measure> measures;

  RhythmScore({
    required this.title,
    required this.tempoBpm,
    this.instrument = Instrument.snare,
    required this.measures,
  }) : assert(measures.isNotEmpty);

  factory RhythmScore.empty({
    String title = 'Untitled',
    int tempoBpm = 100,
    TimeSignature meter = TimeSignature.common,
    Instrument instrument = Instrument.snare,
    int measuresCount = RhythmGrid.defaultMeasuresCount,
  }) {
    return RhythmScore(
      title: title,
      tempoBpm: tempoBpm,
      instrument: instrument,
      measures: List.generate(measuresCount, (_) => Measure.empty(meter: meter)),
    );
  }

  RhythmScore copyWith({
    String? title,
    int? tempoBpm,
    Instrument? instrument,
    List<Measure>? measures,
  }) {
    return RhythmScore(
      title: title ?? this.title,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      instrument: instrument ?? this.instrument,
      measures: measures ?? this.measures,
    );
  }

  RhythmScore copyWithMeasure(int measureIndex, Measure measure) {
    final updated = List<Measure>.of(measures);
    updated[measureIndex] = measure;
    return copyWith(measures: updated);
  }

  /// Where each measure starts, in [RhythmGrid] units from the start of the
  /// score -- with one more entry at the end, where the score ends.
  List<int> get measureStartUnits {
    final starts = [0];
    for (final measure in measures) {
      starts.add(starts.last + measure.capacityUnits);
    }
    return starts;
  }

  /// The whole score's length in [RhythmGrid] units.
  int get totalUnits => measureStartUnits.last;

  /// Which measure [units] (from the start of the score) falls in -- the
  /// first or last measure for a position before or past the score.
  int measureIndexAt(double units) {
    final starts = measureStartUnits;
    for (var index = 0; index < measures.length; index++) {
      if (units < starts[index + 1]) return index;
    }
    return measures.length - 1;
  }

  /// Changes the time signature from measure [measureIndex] on: that
  /// measure takes [meter] (keeping as many of its events as fit -- see
  /// [Measure.withMeter]), and so does every later measure that has no
  /// notes yet. A later measure that already has notes keeps its own time
  /// signature and content untouched. Earlier measures are never changed.
  ///
  /// A later measure with only rests counts as having no notes (its rests
  /// are dropped): saving and reopening a score fills empty measures with
  /// rests, and they shouldn't stop following meter changes because of it.
  RhythmScore withMeterFrom(int measureIndex, TimeSignature meter) {
    final updated = List<Measure>.of(measures);
    updated[measureIndex] = measures[measureIndex].withMeter(meter);
    for (var index = measureIndex + 1; index < measures.length; index++) {
      if (!measures[index].hasNotes) updated[index] = Measure.empty(meter: meter);
    }
    return copyWith(measures: updated);
  }

  /// Where every note (not rest) starts, in [RhythmGrid] units from the
  /// start of the score, in playing order.
  List<int> get noteStartUnits {
    final starts = <int>[];
    final measureStarts = measureStartUnits;
    for (var measureIndex = 0; measureIndex < measures.length; measureIndex++) {
      var unit = measureStarts[measureIndex];
      for (final event in measures[measureIndex].events) {
        if (!event.isRest) starts.add(unit);
        unit += event.durationUnits;
      }
    }
    return starts;
  }

  /// The stretches where nothing should be played, as (start, end) in
  /// [RhythmGrid] units from the start of the score: every rest, and any
  /// unfilled space at the end of a measure (it plays as silence, and is
  /// filled in as rests when the score is saved and reopened). Back-to-back
  /// rests come out as one stretch.
  List<(int, int)> get restSpanUnits {
    final spans = <(int, int)>[];
    void addSilence(int start, int end) {
      if (end <= start) return;
      if (spans.isNotEmpty && spans.last.$2 == start) {
        spans[spans.length - 1] = (spans.last.$1, end);
      } else {
        spans.add((start, end));
      }
    }

    final measureStarts = measureStartUnits;
    for (var measureIndex = 0; measureIndex < measures.length; measureIndex++) {
      var unit = measureStarts[measureIndex];
      for (final event in measures[measureIndex].events) {
        if (event.isRest) addSilence(unit, unit + event.durationUnits);
        unit += event.durationUnits;
      }
      addSilence(unit, measureStarts[measureIndex + 1]);
    }
    return spans;
  }

  /// Appends one new empty measure to the end of the score, in the last
  /// measure's time signature.
  RhythmScore appendMeasure() =>
      copyWith(measures: [...measures, Measure.empty(meter: measures.last.meter)]);

  @override
  bool operator ==(Object other) =>
      other is RhythmScore &&
      other.title == title &&
      other.tempoBpm == tempoBpm &&
      other.instrument == instrument &&
      listEquals(other.measures, measures);

  @override
  int get hashCode => Object.hash(title, tempoBpm, instrument, Object.hashAll(measures));
}
