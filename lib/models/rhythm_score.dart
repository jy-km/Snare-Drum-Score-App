import 'package:flutter/foundation.dart';

/// Grid dimensions. Every duration and position is an integer count of
/// "units", where one unit is 1/[unitsPerQuarterNote] of a quarter note --
/// the coarsest resolution at which both a sixteenth note (3 units) and an
/// eighth-note triplet (4 units) are whole numbers. The time signature is
/// per-measure (see [TimeSignature]) -- numerator within
/// [minBeatsPerMeasure]..[maxBeatsPerMeasureFor], denominator one of
/// [beatUnits] (quarter-, half- or eighth-note beats). The number of measures is
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
  /// original/default), a half-note beat (2) or an eighth-note beat (8).
  /// Listed in the order the meter menu shows them.
  static const List<int> beatUnits = [4, 2, 8];
  static const int defaultBeatUnit = 4;

  /// The numerator's upper bound depends on the denominator: 1/4..16/4,
  /// 1/2..8/2 and 1/8..16/8.
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
  static const common = TimeSignature(
    RhythmGrid.defaultBeatsPerMeasure,
    RhythmGrid.defaultBeatUnit,
  );

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

/// The note a score's tempo counts: "150 BPM" in [half] notes is 150 half
/// notes -- 300 quarter notes -- a minute. Independent of the time
/// signature; the count-in still clicks the meter's own beat.
enum TempoBeat {
  eighth(RhythmGrid.unitsPerQuarterNote ~/ 2, '1/8'),
  quarter(RhythmGrid.unitsPerQuarterNote, '1/4'),

  /// A quarter note and a half: the beat of 6/8, 9/8 and 12/8 felt in
  /// twos, threes and fours.
  dottedQuarter(RhythmGrid.unitsPerQuarterNote * 3 ~/ 2, '1/4.'),
  half(RhythmGrid.unitsPerQuarterNote * 2, '1/2');

  /// Length of one beat in [RhythmGrid] units.
  final int units;

  /// As the editor's note-length buttons write it.
  final String label;

  const TempoBeat(this.units, this.label);

  /// Milliseconds per [RhythmGrid] unit at [bpm] of these beats.
  double msPerUnit(num bpm) => 60000 / bpm / units;

  /// [bpm] of [from] beats, counted in these beats instead.
  double convert(num bpm, TempoBeat from) => bpm * from.units / units;

  /// "150 BPM", with the beat note written out unless it is the usual
  /// quarter note: "150 BPM (1/2)".
  String describe(int bpm) => this == quarter ? '$bpm BPM' : '$bpm BPM ($label)';
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
/// one quarter note. Likewise three [quarterTriplet]s span a half note (three
/// notes across two beats) and three [sixteenthTriplet]s an eighth note (six
/// to the beat).
enum NoteValue { half, quarter, eighth, eighthTriplet, sixteenth, quarterTriplet, sixteenthTriplet }

extension NoteValueUnits on NoteValue {
  /// Duration in [RhythmGrid] units (out of a measure's capacity, which
  /// depends on the score's meter).
  int get units {
    switch (this) {
      case NoteValue.half:
        return 24;
      case NoteValue.quarter:
        return 12;
      case NoteValue.eighth:
        return 6;
      case NoteValue.eighthTriplet:
        return 4;
      case NoteValue.sixteenth:
        return 3;
      case NoteValue.quarterTriplet:
        return 8;
      case NoteValue.sixteenthTriplet:
        return 2;
    }
  }

  /// Whether this is one note of a triplet -- written under a "3".
  bool get isTriplet =>
      this == NoteValue.quarterTriplet ||
      this == NoteValue.eighthTriplet ||
      this == NoteValue.sixteenthTriplet;
}

/// [marcato] is a note hit harder still than an [accent], written with a
/// "^" over it instead of a ">".
enum EventType { rest, normal, accent, marcato }

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
      case EventType.marcato:
        return 127;
    }
  }
}

/// Something added to a note, at most one at a time. A [flam] or [drag]
/// (also called a ruff) is grace strokes played just before the note,
/// leading into it -- one for a flam, two for a drag -- which take no time
/// of their own in the measure. A [roll] is the note played as a run of
/// strokes filling its length. Listed in the order they are saved by (see
/// `MidiScoreCodec`), so new ones go at the end.
enum Ornament { none, flam, drag, roll }

extension OrnamentGraceNotes on Ornament {
  /// How many grace strokes come before the main note.
  int get graceNoteCount {
    switch (this) {
      case Ornament.none:
      case Ornament.roll:
        return 0;
      case Ornament.flam:
        return 1;
      case Ornament.drag:
        return 2;
    }
  }
}

/// A dynamic marking, softest first. Not a fixed loudness: what one means
/// is only judged against the others in the same score, as played (see
/// `DynamicsCheck`).
enum DynamicMark { pp, p, mp, mf, f, ff }

/// A crescendo (getting louder) or decrescendo (getting softer), written as
/// a hairpin under the staff.
enum Hairpin { crescendo, decrescendo }

/// One rhythmic token: a note or rest of a given [value] (duration). A
/// note may have an [ornament], and dynamics written at it: a
/// [dynamicMark] that holds from this note on, and the start or end of a
/// hairpin ([hairpinStart], [hairpinEnd] -- see [RhythmScore.hairpinSpans]).
/// A rest has none of these.
class RhythmEvent {
  final NoteValue value;
  final EventType type;
  final Ornament ornament;
  final DynamicMark? dynamicMark;
  final Hairpin? hairpinStart;
  final bool hairpinEnd;

  const RhythmEvent(
    this.value,
    this.type, {
    Ornament ornament = Ornament.none,
    DynamicMark? dynamicMark,
    Hairpin? hairpinStart,
    bool hairpinEnd = false,
  }) : ornament = type == EventType.rest ? Ornament.none : ornament,
       dynamicMark = type == EventType.rest ? null : dynamicMark,
       hairpinStart = type == EventType.rest ? null : hairpinStart,
       hairpinEnd = type == EventType.rest ? false : hairpinEnd;

  int get durationUnits => value.units;

  bool get isRest => type == EventType.rest;

  int get velocity => type.velocity;

  /// Whether any dynamic is written at this note.
  bool get hasDynamics => dynamicMark != null || hairpinStart != null || hairpinEnd;

  /// This event with the given parts changed -- keeping its dynamics,
  /// which a new event would lose. The `clear...` flags remove one.
  RhythmEvent copyWith({
    NoteValue? value,
    EventType? type,
    Ornament? ornament,
    DynamicMark? dynamicMark,
    bool clearDynamicMark = false,
    Hairpin? hairpinStart,
    bool clearHairpinStart = false,
    bool? hairpinEnd,
  }) => RhythmEvent(
    value ?? this.value,
    type ?? this.type,
    ornament: ornament ?? this.ornament,
    dynamicMark: clearDynamicMark ? null : dynamicMark ?? this.dynamicMark,
    hairpinStart: clearHairpinStart ? null : hairpinStart ?? this.hairpinStart,
    hairpinEnd: hairpinEnd ?? this.hairpinEnd,
  );

  @override
  bool operator ==(Object other) =>
      other is RhythmEvent &&
      other.value == value &&
      other.type == type &&
      other.ornament == ornament &&
      other.dynamicMark == dynamicMark &&
      other.hairpinStart == hairpinStart &&
      other.hairpinEnd == hairpinEnd;

  @override
  int get hashCode => Object.hash(value, type, ornament, dynamicMark, hairpinStart, hairpinEnd);
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

  /// Whether the event at [index] could become [value] long without the
  /// measure overflowing.
  bool canReplace(int index, NoteValue value) =>
      filledUnits - events[index].durationUnits + value.units <= capacityUnits;

  /// This measure with the event at [index] swapped for [event]; everything
  /// after it moves to make room (or close up).
  Measure replaceAt(int index, RhythmEvent event) {
    assert(canReplace(index, event.value));
    return Measure([...events]..[index] = event, meter: meter);
  }

  /// This measure without the event at [index]; everything after it moves
  /// up to close the gap.
  Measure removeAt(int index) => Measure([...events]..removeAt(index), meter: meter);

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

  /// The note [tempoBpm] counts.
  final TempoBeat tempoBeat;

  /// Which drum sounds for every hit in this score.
  final Instrument instrument;

  /// Each with its own time signature (see [Measure.meter]).
  final List<Measure> measures;

  RhythmScore({
    required this.title,
    required this.tempoBpm,
    this.tempoBeat = TempoBeat.quarter,
    this.instrument = Instrument.snare,
    required this.measures,
  }) : assert(measures.isNotEmpty);

  factory RhythmScore.empty({
    String title = 'Untitled',
    int tempoBpm = 100,
    TempoBeat tempoBeat = TempoBeat.quarter,
    TimeSignature meter = TimeSignature.common,
    Instrument instrument = Instrument.snare,
    int measuresCount = RhythmGrid.defaultMeasuresCount,
  }) {
    return RhythmScore(
      title: title,
      tempoBpm: tempoBpm,
      tempoBeat: tempoBeat,
      instrument: instrument,
      measures: List.generate(measuresCount, (_) => Measure.empty(meter: meter)),
    );
  }

  RhythmScore copyWith({
    String? title,
    int? tempoBpm,
    TempoBeat? tempoBeat,
    Instrument? instrument,
    List<Measure>? measures,
  }) {
    return RhythmScore(
      title: title ?? this.title,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      tempoBeat: tempoBeat ?? this.tempoBeat,
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

  /// Which notes have grace strokes before them (a flam or drag), as indexes
  /// into [noteStartUnits].
  Set<int> get graceNoteIndexes {
    final indexes = <int>{};
    var noteIndex = 0;
    for (final measure in measures) {
      for (final event in measure.events) {
        if (event.isRest) continue;
        if (event.ornament.graceNoteCount > 0) indexes.add(noteIndex);
        noteIndex++;
      }
    }
    return indexes;
  }

  /// Every note (not rest) in playing order -- the order [noteStartUnits]
  /// and the judge number them in.
  List<RhythmEvent> get notes => [
    for (final measure in measures)
      for (final event in measure.events)
        if (!event.isRest) event,
  ];

  /// Where each note is: (measure index, event index in that measure), by
  /// note index.
  List<(int, int)> get noteEventIndexes => [
    for (var measure = 0; measure < measures.length; measure++)
      for (var event = 0; event < measures[measure].events.length; event++)
        if (!measures[measure].events[event].isRest) (measure, event),
  ];

  /// The dynamic marking each note is played at -- the latest one written
  /// at or before it -- by note index. Null before the first marking.
  List<DynamicMark?> get dynamicMarkAtNotes {
    DynamicMark? current;
    return [for (final note in notes) current = note.dynamicMark ?? current];
  }

  /// Every hairpin, as which notes it covers. One runs from the note it
  /// starts at to the first note from there on marked as its end; with no
  /// end marked, it runs up to the next note with a dynamic marking
  /// (included -- it leads into it), or else to the last note. A new
  /// hairpin starting first ends it at the note before.
  List<HairpinSpan> get hairpinSpans {
    final all = notes;
    final spans = <HairpinSpan>[];
    for (var start = 0; start < all.length; start++) {
      final kind = all[start].hairpinStart;
      if (kind == null) continue;
      var end = all.length - 1;
      for (var index = start; index < all.length; index++) {
        if (all[index].hairpinEnd) {
          end = index;
          break;
        }
        if (index > start && all[index].hairpinStart != null) {
          end = index - 1;
          break;
        }
        if (index > start && all[index].dynamicMark != null) {
          end = index;
          break;
        }
      }
      spans.add(HairpinSpan(kind, start, end));
    }
    return spans;
  }

  /// The parts of hairpins under measure [measureIndex], to draw: each from
  /// where it starts in this measure (or the measure's start, if it began
  /// earlier) to where it ends (or the measure's end, if it goes on), with
  /// how far through the whole hairpin each end is.
  List<HairpinSegment> hairpinSegmentsIn(int measureIndex) {
    final starts = noteStartUnits;
    final all = notes;
    final measureStarts = measureStartUnits;
    final measureStart = measureStarts[measureIndex];
    final measureEnd = measureStarts[measureIndex + 1];
    final segments = <HairpinSegment>[];
    for (final span in hairpinSpans) {
      final from = starts[span.firstNote].toDouble();
      // To the middle of its last note -- under the note it leads into --
      // or just short of it, when a marking is written there.
      final last = all[span.lastNote];
      final to = last.dynamicMark != null && span.lastNote > span.firstNote
          ? starts[span.lastNote].toDouble()
          : starts[span.lastNote] + last.durationUnits / 2;
      if (to <= measureStart || from >= measureEnd) continue;
      final length = to - from;
      final segmentFrom = from < measureStart ? measureStart.toDouble() : from;
      final segmentTo = to > measureEnd ? measureEnd.toDouble() : to;
      segments.add(
        HairpinSegment(
          span.kind,
          startUnits: segmentFrom - measureStart,
          endUnits: segmentTo - measureStart,
          startFraction: (segmentFrom - from) / length,
          endFraction: (segmentTo - from) / length,
        ),
      );
    }
    return segments;
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

  /// This score without measure [measureIndex]. A score always keeps at
  /// least one measure.
  RhythmScore removeMeasure(int measureIndex) {
    assert(measures.length > 1);
    return copyWith(measures: [...measures]..removeAt(measureIndex));
  }

  /// Appends one new empty measure to the end of the score, in the last
  /// measure's time signature.
  RhythmScore appendMeasure() => copyWith(
    measures: [
      ...measures,
      Measure.empty(meter: measures.last.meter),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is RhythmScore &&
      other.title == title &&
      other.tempoBpm == tempoBpm &&
      other.tempoBeat == tempoBeat &&
      other.instrument == instrument &&
      listEquals(other.measures, measures);

  @override
  int get hashCode => Object.hash(title, tempoBpm, tempoBeat, instrument, Object.hashAll(measures));
}

/// A hairpin, as the notes it covers (indexes into [RhythmScore.notes]).
class HairpinSpan {
  final Hairpin kind;
  final int firstNote;
  final int lastNote;

  const HairpinSpan(this.kind, this.firstNote, this.lastNote);

  @override
  bool operator ==(Object other) =>
      other is HairpinSpan &&
      other.kind == kind &&
      other.firstNote == firstNote &&
      other.lastNote == lastNote;

  @override
  int get hashCode => Object.hash(kind, firstNote, lastNote);

  @override
  String toString() => 'HairpinSpan(${kind.name}, $firstNote-$lastNote)';
}

/// The part of a hairpin drawn under one measure: from [startUnits] to
/// [endUnits] within it, and how far through the whole hairpin (0 to 1)
/// each end is -- so a crescendo split over two measures opens up across
/// both.
class HairpinSegment {
  final Hairpin kind;
  final double startUnits;
  final double endUnits;
  final double startFraction;
  final double endFraction;

  const HairpinSegment(
    this.kind, {
    required this.startUnits,
    required this.endUnits,
    required this.startFraction,
    required this.endFraction,
  });
}
