import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/run_review.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

void main() {
  // 60 BPM, two measures of four quarter notes: notes at 4-7s and 8-11s,
  // after a 4s count-in.
  RunReview review() {
    var measure = Measure.empty();
    for (var i = 0; i < 4; i++) {
      measure = measure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    }
    final score = RhythmScore(title: 'Groove', tempoBpm: 60, measures: [measure, measure]);
    return RunReview(
      layout: TimelineLayout(score),
      secondsPerUnit: 1 / 12,
      noteTimes: [for (var i = 0; i < 8; i++) 4.0 + i],
      judgements: const [
        JudgedHit(Judgement.perfect, noteIndex: 0, offsetSeconds: 0.01, hitTimeSeconds: 4.01),
        JudgedHit(Judgement.good, noteIndex: 1, offsetSeconds: 0.1, hitTimeSeconds: 5.1),
        JudgedHit(Judgement.great, noteIndex: 2, offsetSeconds: -0.06, hitTimeSeconds: 5.94),
        JudgedHit(Judgement.miss, noteIndex: 3),
        JudgedHit(Judgement.perfect, noteIndex: 4, offsetSeconds: 0, hitTimeSeconds: 8.0),
        JudgedHit(Judgement.fail, hitTimeSeconds: 8.5),
        JudgedHit(Judgement.good, noteIndex: 5, offsetSeconds: -0.115, hitTimeSeconds: 8.885),
        JudgedHit(Judgement.perfect, noteIndex: 6, offsetSeconds: 0.02, hitTimeSeconds: 10.02),
        JudgedHit(Judgement.perfect, noteIndex: 7, offsetSeconds: 0, hitTimeSeconds: 11.0),
      ],
      counts: const {
        Judgement.perfect: 4,
        Judgement.great: 1,
        Judgement.good: 2,
        Judgement.miss: 1,
        Judgement.fail: 1,
      },
      audio: Int16List(44100 * 12),
      sampleRate: 44100,
      timingEstimated: false,
    );
  }

  Future<void> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ReviewScreen(review: review())));
  }

  List<StaffMark> marksOf(WidgetTester tester, int timelineMeasure) => tester
      .widget<StaffNotationView>(find.byKey(Key('review_measure_$timelineMeasure')))
      .marks;

  testWidgets('Shows the tally, the notes most off, and the missed notes', (tester) async {
    await pumpReview(tester);

    expect(find.text('Perfect 4  ·  Great 1  ·  Good 2  ·  Miss 1  ·  Fail 1'), findsOneWidget);
    // Worst first: 115ms early, then 100ms late, then 60ms early.
    final lines = [
      for (final key in ['review_most_off_5', 'review_most_off_1', 'review_most_off_2'])
        tester.getTopLeft(find.byKey(Key(key))).dy,
    ];
    expect(lines, orderedEquals([...lines]..sort()));
    expect(find.text('Measure 2, note 2: Good-, -115 ms (early)'), findsOneWidget);
    expect(find.text('Measure 1, note 2: Good+, +100 ms (late)'), findsOneWidget);
    expect(find.text('Measure 1, note 3: Great-, -60 ms (early)'), findsOneWidget);
    expect(find.text('Measure 1, note 4'), findsOneWidget, reason: 'under Missed');
  });

  testWidgets('Every measure of the run is shown with its hits marked and labelled',
      (tester) async {
    await pumpReview(tester);

    // Count-in plus both measures, all on the one page.
    expect(find.byType(StaffNotationView, skipOffstage: false), findsNWidgets(3));

    final first = marksOf(tester, 1);
    expect(first.length, 4);
    expect(first.map((m) => m.label), [null, '+100', '-60', null]);
    expect(first.last.isAbsence, isTrue, reason: 'the missed note');

    final second = marksOf(tester, 2);
    expect(second.length, 5, reason: '4 notes and the fail');
    expect(second.where((m) => m.label == '-115').length, 1);
  });

  testWidgets('Replay moves a playhead through the measures in time, and can be stopped',
      (tester) async {
    await pumpReview(tester);
    double? playheadIn(int measure) => tester
        .widget<StaffNotationView>(find.byKey(Key('review_measure_$measure'), skipOffstage: false))
        .playheadUnits;

    await tester.tap(find.byKey(const Key('review_play_button')));
    await tester.pump();
    // No audio in tests: the playhead starts on the clock after a second.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(playheadIn(0), closeTo(24, 1), reason: '2s in: halfway through the count-in');

    await tester.pump(const Duration(seconds: 3));
    expect(playheadIn(0), isNull);
    expect(playheadIn(1), closeTo(12, 1), reason: '5s in: beat 2 of measure 1');

    await tester.tap(find.byKey(const Key('review_stop_button')));
    await tester.pump();
    expect(playheadIn(1), isNull);
    expect(find.byKey(const Key('review_play_button')), findsOneWidget);
  });

  testWidgets('Replay ends by itself at the end of the recording', (tester) async {
    await pumpReview(tester);

    await tester.tap(find.byKey(const Key('review_play_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(const Key('review_play_button')), findsOneWidget);
  });
}
