import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/practice_history.dart';
import 'package:snare_drum_score_app/widgets/accuracy_chart.dart';

import 'support/review_fixture.dart';

void main() {
  group('Accuracy', () {
    Map<Judgement, int> counts({
      int perfect = 0,
      int great = 0,
      int good = 0,
      int miss = 0,
      int fail = 0,
    }) =>
        {
          Judgement.perfect: perfect,
          Judgement.great: great,
          Judgement.good: good,
          Judgement.miss: miss,
          Judgement.fail: fail,
        };

    test('Perfect 100%, Great 75%, Good 50%, Miss 0%, averaged over the notes', () {
      expect(runAccuracy(counts(perfect: 4)), 1.0);
      expect(runAccuracy(counts(perfect: 1, great: 1, good: 1, miss: 1)), closeTo(0.5625, 1e-9));
      expect(runAccuracy(counts(miss: 3)), 0.0);
    });

    test('Each Fail counts as one more note missed', () {
      expect(runAccuracy(counts(perfect: 3, fail: 1)), 0.75);
    });

    test('Nothing judged has no accuracy', () {
      expect(runAccuracy(counts()), isNull);
      expect(runAccuracy(const {}), isNull);
    });

    test('Shown as a whole percentage', () {
      expect(accuracyText(0.5625), '56%');
    });
  });

  group('File history store', () {
    late Directory root;
    late FilePracticeHistoryStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('history_test');
      store = FilePracticeHistoryStore(root: () async => root);
    });
    tearDown(() => root.delete(recursive: true));

    test('A saved run lists with its details and reloads exactly', () async {
      final review = sampleReview();
      final startedAt = DateTime(2026, 10, 7, 14, 5);

      final saved = await store.save(
        scoreId: 'Groove_1',
        review: review,
        tempoBpm: 60,
        startedAt: startedAt,
      );
      final listed = (await store.runsFor('Groove_1')).single;

      expect(listed.id, saved.id);
      expect(listed.startedAt, startedAt);
      expect(listed.tempoBpm, 60);
      expect(listed.counts, review.counts);
      expect(listed.accuracy, closeTo(0.5625, 1e-9));
      expect(listed.durationSeconds, closeTo(9, 1e-9));
      expect(listed.note, '');

      final reloaded = await store.loadReview(listed);
      expect(reloaded.layout.score, review.layout.score);
      expect(reloaded.secondsPerUnit, review.secondsPerUnit);
      expect(reloaded.noteTimes, review.noteTimes);
      expect(reloaded.audio, review.audio);
      expect(reloaded.sampleRate, review.sampleRate);
      expect(
        reloaded.judgements.map((hit) => (hit.judgement, hit.noteIndex, hit.offsetSeconds)),
        review.judgements.map((hit) => (hit.judgement, hit.noteIndex, hit.offsetSeconds)),
      );
    });

    test('Runs list newest first, per track', () async {
      for (final day in [3, 5, 4]) {
        await store.save(
          scoreId: 'Groove_1',
          review: sampleReview(),
          tempoBpm: 60 + day,
          startedAt: DateTime(2026, 10, day),
        );
      }
      await store.save(
        scoreId: 'Other_2',
        review: sampleReview(),
        tempoBpm: 99,
        startedAt: DateTime(2026, 10, 6),
      );

      expect((await store.runsFor('Groove_1')).map((run) => run.tempoBpm), [65, 64, 63]);
      expect((await store.runsFor('Nothing')), isEmpty);
    });

    test('A note can be added and changed; a run can be deleted; a whole track too', () async {
      final run = await store.save(
        scoreId: 'Groove_1',
        review: sampleReview(),
        tempoBpm: 60,
        startedAt: DateTime(2026, 10, 7),
      );

      await store.updateNote(run, 'rushed the end');
      expect((await store.runsFor('Groove_1')).single.note, 'rushed the end');

      await store.delete(run);
      expect(await store.runsFor('Groove_1'), isEmpty);

      await store.save(
        scoreId: 'Groove_1',
        review: sampleReview(),
        tempoBpm: 60,
        startedAt: DateTime(2026, 10, 8),
      );
      await store.deleteAllFor('Groove_1');
      expect(await store.runsFor('Groove_1'), isEmpty);
    });
  });

  test('Daily accuracy averages each day\'s runs, oldest day first', () {
    PracticeRun run(DateTime when, int perfect, int miss) => PracticeRun(
          id: '${when.millisecondsSinceEpoch}',
          scoreId: 'Groove_1',
          startedAt: when,
          tempoBpm: 60,
          counts: {Judgement.perfect: perfect, Judgement.miss: miss},
          durationSeconds: 10,
          note: '',
          timingEstimated: false,
        );

    final days = DailyAccuracy.fromRuns([
      run(DateTime(2026, 10, 7, 18), 3, 1), // 75%
      run(DateTime(2026, 10, 5, 9), 1, 1), // 50%
      run(DateTime(2026, 10, 7, 8), 4, 0), // 100%
      run(DateTime(2026, 10, 6), 0, 0), // nothing judged: left out
    ]);

    expect(days.map((day) => day.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 7)]);
    expect(days.map((day) => day.averageAccuracy), [0.5, 0.875]);
    expect(days.map((day) => day.runCount), [1, 2]);
  });

  test('Daily tempo keeps each day\'s fastest and slowest tempo, every run counted', () {
    PracticeRun run(DateTime when, int bpm, {int perfect = 1}) => PracticeRun(
          id: '${when.millisecondsSinceEpoch}',
          scoreId: 'Groove_1',
          startedAt: when,
          tempoBpm: bpm,
          counts: {Judgement.perfect: perfect},
          durationSeconds: 10,
          note: '',
          timingEstimated: false,
        );

    final days = DailyTempo.fromRuns([
      run(DateTime(2026, 10, 7, 18), 92),
      run(DateTime(2026, 10, 5, 9), 80),
      run(DateTime(2026, 10, 7, 8), 85),
      run(DateTime(2026, 10, 7, 12), 97, perfect: 0), // nothing judged: still a tempo played
    ]);

    expect(days.map((day) => day.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 7)]);
    expect(days.map((day) => day.topBpm), [80, 97]);
    expect(days.map((day) => day.slowestBpm), [80, 85]);
    expect(days.map((day) => day.runCount), [1, 3]);
  });
}
