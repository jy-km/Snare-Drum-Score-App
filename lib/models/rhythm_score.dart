import 'package:flutter/foundation.dart';

/// Fixed grid dimensions for the v1 rhythm editor: 4/4 time, sixteenth-note
/// resolution, 8 measures.
class RhythmGrid {
  static const int measuresCount = 8;
  static const int beatsPerMeasure = 4;
  static const int subdivisionsPerBeat = 4;
  static const int cellsPerMeasure = beatsPerMeasure * subdivisionsPerBeat;
}

enum BeatState { rest, normal, accent }

extension BeatStateVelocity on BeatState {
  /// MIDI velocity (0-127) representing this state's dynamic.
  int get velocity {
    switch (this) {
      case BeatState.rest:
        return 0;
      case BeatState.normal:
        return 64;
      case BeatState.accent:
        return 110;
    }
  }
}

class Beat {
  final BeatState state;

  const Beat(this.state);

  static const rest = Beat(BeatState.rest);

  bool get isRest => state == BeatState.rest;

  int get velocity => state.velocity;

  /// Cycles rest -> normal -> accent -> rest, matching the tap-grid entry UI.
  Beat get next {
    switch (state) {
      case BeatState.rest:
        return const Beat(BeatState.normal);
      case BeatState.normal:
        return const Beat(BeatState.accent);
      case BeatState.accent:
        return const Beat(BeatState.rest);
    }
  }

  @override
  bool operator ==(Object other) => other is Beat && other.state == state;

  @override
  int get hashCode => state.hashCode;
}

class Measure {
  final List<Beat> beats;

  Measure(this.beats) : assert(beats.length == RhythmGrid.cellsPerMeasure);

  factory Measure.empty() => Measure(
        List.generate(RhythmGrid.cellsPerMeasure, (_) => Beat.rest),
      );

  Measure copyWithBeat(int cellIndex, Beat beat) {
    final updated = List<Beat>.of(beats);
    updated[cellIndex] = beat;
    return Measure(updated);
  }

  @override
  bool operator ==(Object other) =>
      other is Measure && listEquals(other.beats, beats);

  @override
  int get hashCode => Object.hashAll(beats);
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
