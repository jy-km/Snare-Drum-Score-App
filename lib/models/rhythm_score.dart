import 'package:flutter/foundation.dart';

/// Fixed grid dimensions: 4/4 time, sixteenth-note resolution, 8 measures.
class RhythmGrid {
  static const int measuresCount = 8;
  static const int beatsPerMeasure = 4;
  static const int subdivisionsPerBeat = 4;
  static const int unitsPerMeasure = beatsPerMeasure * subdivisionsPerBeat;
}

enum NoteValue { quarter, eighth, sixteenth }

extension NoteValueUnits on NoteValue {
  /// Duration in sixteenth-note units (out of [RhythmGrid.unitsPerMeasure]).
  int get sixteenthUnits {
    switch (this) {
      case NoteValue.quarter:
        return 4;
      case NoteValue.eighth:
        return 2;
      case NoteValue.sixteenth:
        return 1;
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

  int get durationUnits => value.sixteenthUnits;

  bool get isRest => type == EventType.rest;

  int get velocity => type.velocity;

  @override
  bool operator ==(Object other) =>
      other is RhythmEvent && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);
}

/// A measure built by appending [RhythmEvent]s left to right (append-only
/// entry for v1). Always filled to at most [RhythmGrid.unitsPerMeasure];
/// never overfilled.
class Measure {
  final List<RhythmEvent> events;

  Measure(this.events)
      : assert(_totalUnits(events) <= RhythmGrid.unitsPerMeasure);

  factory Measure.empty() => Measure(const []);

  static int _totalUnits(List<RhythmEvent> events) =>
      events.fold(0, (sum, e) => sum + e.durationUnits);

  int get filledUnits => _totalUnits(events);

  int get remainingUnits => RhythmGrid.unitsPerMeasure - filledUnits;

  bool get isComplete => remainingUnits == 0;

  bool canAppend(NoteValue value) => value.sixteenthUnits <= remainingUnits;

  Measure appendEvent(RhythmEvent event) {
    assert(canAppend(event.value));
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

  final List<Measure> measures;

  RhythmScore({
    required this.title,
    required this.tempoBpm,
    required this.measures,
  }) : assert(measures.length == RhythmGrid.measuresCount);

  factory RhythmScore.empty({String title = 'Untitled', int tempoBpm = 100}) {
    return RhythmScore(
      title: title,
      tempoBpm: tempoBpm,
      measures: List.generate(
        RhythmGrid.measuresCount,
        (_) => Measure.empty(),
      ),
    );
  }

  RhythmScore copyWith({String? title, int? tempoBpm, List<Measure>? measures}) {
    return RhythmScore(
      title: title ?? this.title,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      measures: measures ?? this.measures,
    );
  }

  RhythmScore copyWithMeasure(int measureIndex, Measure measure) {
    final updated = List<Measure>.of(measures);
    updated[measureIndex] = measure;
    return copyWith(measures: updated);
  }

  @override
  bool operator ==(Object other) =>
      other is RhythmScore &&
      other.title == title &&
      other.tempoBpm == tempoBpm &&
      listEquals(other.measures, measures);

  @override
  int get hashCode => Object.hash(title, tempoBpm, Object.hashAll(measures));
}
