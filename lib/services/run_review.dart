import 'dart:typed_data';

import 'hit_judge.dart';
import 'timeline_layout.dart';

/// Everything kept from a judged practice run so it can be gone over
/// afterwards: what was judged, and what the microphone heard.
class RunReview {
  final TimelineLayout layout;

  /// The run's tempo, as seconds per [RhythmGrid] unit.
  final double secondsPerUnit;

  /// When each of the score's notes was due, in seconds from the start of
  /// the count-in.
  final List<double> noteTimes;

  /// Every judgement of the run, in the order they happened.
  final List<JudgedHit> judgements;

  final Map<Judgement, int> counts;

  /// The microphone's recording, starting at the start of the count-in --
  /// so a moment in it and the same moment on the timeline are the same
  /// number of seconds in.
  final Int16List audio;
  final int sampleRate;

  /// Whether hits were placed by estimate because the count-in wasn't heard
  /// (see `LiveJudge.timingIsEstimated`).
  final bool timingEstimated;

  RunReview({
    required this.layout,
    required this.secondsPerUnit,
    required this.noteTimes,
    required List<JudgedHit> judgements,
    required this.counts,
    required this.audio,
    required this.sampleRate,
    required this.timingEstimated,
  }) : judgements = List.unmodifiable(judgements);

  double get audioSeconds => audio.length / sampleRate;

  /// The [count] notes that were hit furthest from their time, worst first
  /// -- the ones worth practising. Only Greats and Goods: a Perfect isn't
  /// off by anything worth fixing, and a Miss has no timing to rank.
  List<JudgedHit> mostOff({int count = 3}) {
    final offNotes = judgements
        .where((hit) =>
            (hit.judgement == Judgement.great || hit.judgement == Judgement.good) &&
            hit.offsetSeconds != null)
        .toList()
      ..sort((a, b) => b.offsetSeconds!.abs().compareTo(a.offsetSeconds!.abs()));
    return offNotes.take(count).toList();
  }

  /// The notes nobody hit, in order.
  List<JudgedHit> get missedNotes =>
      judgements.where((hit) => hit.judgement == Judgement.miss).toList();

  /// Where a judged note is in the score, e.g. "Measure 3, note 2".
  String locate(JudgedHit hit) {
    final (measure, note) = layout.noteLocations[hit.noteIndex!];
    return 'Measure $measure, note $note';
  }

  /// Which timeline measure a judged note is in (count-in = 0).
  int timelineMeasureOf(JudgedHit hit) => layout.noteLocations[hit.noteIndex!].$1;
}
