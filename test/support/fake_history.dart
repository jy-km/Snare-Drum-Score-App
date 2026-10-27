import 'dart:typed_data';

import 'package:snare_drum_score_app/services/practice_history.dart';
import 'package:snare_drum_score_app/services/run_review.dart';

/// Keeps practice runs in memory, through the same JSON encoding the real
/// store writes.
class InMemoryPracticeHistoryStore implements PracticeHistoryStore {
  /// Run JSON and recording, by track then run id.
  final runs = <String, Map<String, (Map<String, Object?>, Int16List)>>{};

  @override
  Future<PracticeRun> save({
    required String scoreId,
    required RunReview review,
    required int tempoBpm,
    required DateTime startedAt,
    RunSection? section,
  }) async {
    final run = PracticeRun(
      id: '${startedAt.millisecondsSinceEpoch}',
      scoreId: scoreId,
      startedAt: startedAt,
      tempoBpm: tempoBpm,
      tempoBeat: review.layout.score.tempoBeat,
      counts: review.counts,
      durationSeconds: review.audioSeconds,
      note: '',
      timingEstimated: review.timingEstimated,
      section: section,
    );
    (runs[scoreId] ??= {})[run.id] = (encodeRun(run, review), review.audio);
    return run;
  }

  @override
  Future<List<PracticeRun>> runsFor(String scoreId) async {
    final list = [
      for (final (json, _) in (runs[scoreId] ?? const {}).values)
        decodeRunSummary(json.cast<String, dynamic>()),
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  @override
  Future<RunReview> loadReview(PracticeRun run) async {
    final (json, audio) = runs[run.scoreId]![run.id]!;
    return decodeReview(json.cast<String, dynamic>(), audio);
  }

  @override
  Future<void> updateNote(PracticeRun run, String note) async {
    final (json, audio) = runs[run.scoreId]![run.id]!;
    runs[run.scoreId]![run.id] = ({...json, 'note': note}, audio);
  }

  @override
  Future<void> delete(PracticeRun run) async => runs[run.scoreId]?.remove(run.id);

  @override
  Future<void> deleteAllFor(String scoreId) async => runs.remove(scoreId);
}
