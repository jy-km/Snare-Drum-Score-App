import 'package:flutter/foundation.dart';

/// Grid dimensions. Every duration and position is an integer count of
/// "units", where one unit is 1/[unitsPerQuarterNote] of a quarter note --
/// the coarsest resolution at which both a sixteenth note (3 units) and an
/// eighth-note triplet (4 units) are whole numbers. The time signature is
/// per-score and adjustable -- numerator ([RhythmScore.beatsPerMeasure])
/// within [minBeatsPerMeasure]..[maxBeatsPerMeasureFor], denominator
/// ([RhythmScore.beatUnit]) one of [beatUnits] (quarter-note or half-note
/// beats). The number of measures is also per-score and growable (see
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

  /// Units for a measure at [defaultBeatsPerMeasure]/[defaultBeatUnit] (4/4)
  /// -- used as the default capacity for [Measure] methods called without an
  /// explicit score context.
  static const int defaultUnitsPerMeasure = defaultBeatsPerMeasure * unitsPerQuarterNote;
}

/// Which drum sounds when a note is hit. Chosen per-score, the same way
/// [RhythmScore.beatsPerMeasure] is -- affects both verification/practice
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
/// entry for v1). Always filled to at most the measure's capacity (in
/// [RhythmGrid] units, per the score's meter); never
/// overfilled. Capacity defaults to [RhythmGrid.defaultUnitsPerMeasure] (4/4)
/// for callers without a specific score's meter in hand.
class Measure {
  final List<RhythmEvent> events;

  Measure(this.events);

  factory Measure.empty() => Measure(const []);

  static int _totalUnits(List<RhythmEvent> events) =>
      events.fold(0, (sum, e) => sum + e.durationUnits);

  int get filledUnits => _totalUnits(events);

  /// Remaining capacity at the default 4/4 measure size. For a specific
  /// score's meter, compare [filledUnits] against `score.unitsPerMeasure`
  /// directly (see [canAppend]).
  int get remainingUnits => RhythmGrid.defaultUnitsPerMeasure - filledUnits;

  /// Whether this measure is filled at the default 4/4 measure size.
  bool get isComplete => remainingUnits == 0;

  bool canAppend(NoteValue value, [int unitsPerMeasure = RhythmGrid.defaultUnitsPerMeasure]) =>
      value.units <= unitsPerMeasure - filledUnits;

  Measure appendEvent(RhythmEvent event,
      [int unitsPerMeasure = RhythmGrid.defaultUnitsPerMeasure]) {
    assert(canAppend(event.value, unitsPerMeasure));
    return Measure([...events, event]);
  }

  Measure removeLast() {
    if (events.isEmpty) return this;
    return Measure(events.sublist(0, events.length - 1));
  }

  @override
  bool operator ==(Object other) =>
      other is Measure && listEquals(other.events, events);

  @override
  int get hashCode => Object.hashAll(events);
}

class RhythmScore {
  final String title;

  /// The target tempo the piece is meant to be played at (BPM). Distinct
  /// from a future, independently adjustable practice-session tempo.
  final int tempoBpm;

  /// Time signature numerator (beats per measure). Must be within
  /// [RhythmGrid.minBeatsPerMeasure]..`RhythmGrid.maxBeatsPerMeasureFor(beatUnit)`.
  final int beatsPerMeasure;

  /// Time signature denominator: 4 (a quarter note is one beat) or 2 (a half
  /// note is one beat). One of [RhythmGrid.beatUnits].
  final int beatUnit;

  /// Which drum sounds for every hit in this score.
  final Instrument instrument;

  final List<Measure> measures;

  /// A measure's capacity in [RhythmGrid] units under this score's meter.
  int get unitsPerMeasure =>
      beatsPerMeasure * (RhythmGrid.unitsPerWholeNote ~/ beatUnit);

  RhythmScore({
    required this.title,
    required this.tempoBpm,
    this.beatsPerMeasure = RhythmGrid.defaultBeatsPerMeasure,
    this.beatUnit = RhythmGrid.defaultBeatUnit,
    this.instrument = Instrument.snare,
    required this.measures,
  })  : assert(measures.isNotEmpty),
        assert(RhythmGrid.beatUnits.contains(beatUnit)),
        assert(beatsPerMeasure >= RhythmGrid.minBeatsPerMeasure &&
            beatsPerMeasure <= RhythmGrid.maxBeatsPerMeasureFor(beatUnit));

  factory RhythmScore.empty({
    String title = 'Untitled',
    int tempoBpm = 100,
    int beatsPerMeasure = RhythmGrid.defaultBeatsPerMeasure,
    int beatUnit = RhythmGrid.defaultBeatUnit,
    Instrument instrument = Instrument.snare,
    int measuresCount = RhythmGrid.defaultMeasuresCount,
  }) {
    return RhythmScore(
      title: title,
      tempoBpm: tempoBpm,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
      instrument: instrument,
      measures: List.generate(
        measuresCount,
        (_) => Measure.empty(),
      ),
    );
  }

  RhythmScore copyWith({
    String? title,
    int? tempoBpm,
    int? beatsPerMeasure,
    int? beatUnit,
    Instrument? instrument,
    List<Measure>? measures,
  }) {
    return RhythmScore(
      title: title ?? this.title,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      beatsPerMeasure: beatsPerMeasure ?? this.beatsPerMeasure,
      beatUnit: beatUnit ?? this.beatUnit,
      instrument: instrument ?? this.instrument,
      measures: measures ?? this.measures,
    );
  }

  RhythmScore copyWithMeasure(int measureIndex, Measure measure) {
    final updated = List<Measure>.of(measures);
    updated[measureIndex] = measure;
    return copyWith(measures: updated);
  }

  /// Appends one new empty measure to the end of the score.
  RhythmScore appendMeasure() => copyWith(measures: [...measures, Measure.empty()]);

  @override
  bool operator ==(Object other) =>
      other is RhythmScore &&
      other.title == title &&
      other.tempoBpm == tempoBpm &&
      other.beatsPerMeasure == beatsPerMeasure &&
      other.beatUnit == beatUnit &&
      other.instrument == instrument &&
      listEquals(other.measures, measures);

  @override
  int get hashCode => Object.hash(
      title, tempoBpm, beatsPerMeasure, beatUnit, instrument, Object.hashAll(measures));
}
