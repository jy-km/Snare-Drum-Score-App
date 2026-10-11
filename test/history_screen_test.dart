import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/history_screen.dart';
import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/widgets/accuracy_chart.dart';

import 'score_list_screen_test.dart' show InMemoryScoreStorage;
import 'support/fake_history.dart';
import 'support/review_fixture.dart';

void main() {
  Future<void> pumpTall(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('Lists the same tracks, in the same order and names, each with one button',
      (tester) async {
    final storage = InMemoryScoreStorage();
    await storage.save('B_Fill_2', RhythmScore.empty(title: 'Fill'));
    await storage.save('A_Groove_1', RhythmScore.empty(title: 'Groove'));
    await pumpTall(
      tester,
      HistoryScreen(storage: storage, historyStore: InMemoryPracticeHistoryStore()),
    );

    expect(
      tester.getTopLeft(find.text('Groove')).dy,
      lessThan(tester.getTopLeft(find.text('Fill')).dy),
      reason: 'same order as the main menu (by file)',
    );
    expect(find.text('View Practice History'), findsNWidgets(2));
    expect(find.byType(OutlinedButton), findsNWidgets(2), reason: 'the only button per track');
  });

  group('A track\'s history', () {
    late InMemoryPracticeHistoryStore history;

    Future<void> pumpTrack(WidgetTester tester) async {
      await pumpTall(
        tester,
        TrackHistoryScreen(scoreId: 'A_Groove_1', title: 'Groove', historyStore: history),
      );
    }

    setUp(() async {
      history = InMemoryPracticeHistoryStore();
      // Two runs on Oct 5 (56% and 100%), one on Oct 7 (56%), at rising tempos.
      await history.save(
        scoreId: 'A_Groove_1',
        review: sampleReview(),
        tempoBpm: 60,
        startedAt: DateTime(2026, 10, 5, 9, 0),
      );
      await history.save(
        scoreId: 'A_Groove_1',
        review: sampleReview(judgements: const [
          JudgedHit(Judgement.perfect, noteIndex: 0, offsetSeconds: 0, hitTimeSeconds: 4),
          JudgedHit(Judgement.perfect, noteIndex: 1, offsetSeconds: 0, hitTimeSeconds: 5),
          JudgedHit(Judgement.perfect, noteIndex: 2, offsetSeconds: 0, hitTimeSeconds: 6),
          JudgedHit(Judgement.perfect, noteIndex: 3, offsetSeconds: 0, hitTimeSeconds: 7),
        ]),
        tempoBpm: 65,
        startedAt: DateTime(2026, 10, 5, 9, 30),
      );
      final latest = await history.save(
        scoreId: 'A_Groove_1',
        review: sampleReview(),
        tempoBpm: 70,
        startedAt: DateTime(2026, 10, 7, 14, 5),
      );
      await history.updateNote(latest, 'rushed the end');
    });

    testWidgets('Charts the average accuracy of each practice day, every run included',
        (tester) async {
      await pumpTrack(tester);

      final chart = tester.widget<AccuracyByDayChart>(find.byType(AccuracyByDayChart));
      expect(chart.days.map((day) => day.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 7)]);
      expect(chart.days.first.averageAccuracy, closeTo((0.5625 + 1) / 2, 1e-9));
      expect(chart.days.first.runCount, 2);
      expect(find.text('3 runs on 2 days. Tap a point for details.'), findsOneWidget);
    });

    testWidgets('Charts the fastest tempo played each day, whatever tempo it was',
        (tester) async {
      await pumpTrack(tester);

      final chart = tester.widget<TempoByDayChart>(find.byType(TempoByDayChart));
      expect(chart.days.map((day) => day.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 7)]);
      expect(chart.days.map((day) => day.topBpm), [65, 70]);
      expect(chart.days.first.slowestBpm, 60);
      expect(chart.days.first.runCount, 2);
      expect(chart.targetBpm, isNull);
      expect(find.text('Fastest tempo by day'), findsOneWidget);
      expect(find.text('The fastest tempo you played each day.'), findsOneWidget);

      // Tapping a point toggles its details without trouble.
      await tester.tap(find.byKey(const Key('tempo_chart')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tempo_chart')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('The tempo chart shows the track\'s tempo as the target', (tester) async {
      await pumpTall(
        tester,
        TrackHistoryScreen(
          scoreId: 'A_Groove_1',
          title: 'Groove',
          historyStore: history,
          targetTempoBpm: 90,
        ),
      );

      expect(tester.widget<TempoByDayChart>(find.byType(TempoByDayChart)).targetBpm, 90);
      expect(
        find.text('The fastest tempo you played each day; the dashed line is the track\'s tempo, 90 BPM.'),
        findsOneWidget,
      );
    });

    testWidgets('Opening a track\'s history from the list passes its tempo as the target',
        (tester) async {
      final storage = InMemoryScoreStorage();
      await storage.save('A_Groove_1', RhythmScore.empty(title: 'Groove', tempoBpm: 84));
      await pumpTall(tester, HistoryScreen(storage: storage, historyStore: history));

      await tester.tap(find.byKey(const Key('view_history_A_Groove_1')));
      await tester.pumpAndSettle();

      expect(tester.widget<TempoByDayChart>(find.byType(TempoByDayChart)).targetBpm, 84);
    });

    testWidgets('Lists every recording, newest first, with tempo, accuracy and note',
        (tester) async {
      await pumpTrack(tester);

      final newest = tester.getTopLeft(find.text('Oct 7, 14:05')).dy;
      final oldest = tester.getTopLeft(find.text('Oct 5, 09:00')).dy;
      expect(newest, lessThan(oldest));
      expect(find.textContaining('70 BPM'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('rushed the end'), findsOneWidget);
      expect(find.text('No note'), findsNWidgets(2));
    });

    testWidgets('Opening a recording shows its review, with its replay', (tester) async {
      await pumpTrack(tester);
      final latestId = '${DateTime(2026, 10, 7, 14, 5).millisecondsSinceEpoch}';

      await tester.tap(find.byKey(Key('open_run_$latestId')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Oct 7, 14:05 · 70 BPM'), findsOneWidget);
      expect(find.text('Accuracy 56%'), findsOneWidget);
      expect(find.text('"rushed the end"'), findsOneWidget);
      expect(find.byKey(const Key('review_play_button')), findsOneWidget);
      expect(find.textContaining('Measure 1, note 3: Good-'), findsOneWidget);
    });

    testWidgets('A note can be edited from the history', (tester) async {
      await pumpTrack(tester);
      final firstId = '${DateTime(2026, 10, 5, 9, 0).millisecondsSinceEpoch}';

      await tester.tap(find.byKey(Key('run_menu_$firstId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_menu_note')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('run_note_field')), 'slow and steady');
      await tester.tap(find.byKey(const Key('run_note_save')));
      await tester.pumpAndSettle();

      expect(find.text('slow and steady'), findsOneWidget);
      final run = (await history.runsFor('A_Groove_1')).last;
      expect(run.note, 'slow and steady');
    });

    testWidgets('A recording can be deleted, after confirming', (tester) async {
      await pumpTrack(tester);
      final firstId = '${DateTime(2026, 10, 5, 9, 0).millisecondsSinceEpoch}';

      await tester.tap(find.byKey(Key('run_menu_$firstId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_run_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Oct 5, 09:00'), findsNothing);
      expect((await history.runsFor('A_Groove_1')).length, 2);
    });

    testWidgets('A track never practised says how its history fills up', (tester) async {
      await pumpTall(
        tester,
        TrackHistoryScreen(scoreId: 'Nothing', title: 'New', historyStore: history),
      );

      expect(find.textContaining('No practice recorded for this track yet'), findsOneWidget);
      expect(find.byType(AccuracyByDayChart), findsNothing);
    });
  });
}
