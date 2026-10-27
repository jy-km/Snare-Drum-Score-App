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
  // The page's own scroll view -- not the sound wave's, which scrolls
  // sideways.
  final page = find.byType(SingleChildScrollView).first;

  // 60 BPM: a 4s count-in, then six measures of four quarter notes, each
  // measure 4s -- 28s in all, every note played on time.
  RunReview sixMeasures() {
    var measure = Measure.empty();
    for (var i = 0; i < 4; i++) {
      measure = measure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
    }
    final score = RhythmScore(title: 'Long', tempoBpm: 60, measures: List.filled(6, measure));
    final noteTimes = [for (var i = 0; i < 24; i++) 4.0 + i];
    return RunReview(
      layout: TimelineLayout(score),
      secondsPerUnit: 1 / 12,
      noteTimes: noteTimes,
      judgements: [
        for (var i = 0; i < 24; i++)
          JudgedHit(
            Judgement.perfect,
            noteIndex: i,
            offsetSeconds: 0,
            hitTimeSeconds: noteTimes[i],
          ),
      ],
      counts: {for (final judgement in Judgement.values) judgement: 0},
      audio: Int16List(28 * 1000),
      sampleRate: 1000,
      timingEstimated: false,
    );
  }

  // With no audio in a test, the replay's playhead starts a second after
  // Replay is tapped (the review screen's fallback).
  const fallback = Duration(seconds: 1);
  const scrollTime = Duration(milliseconds: 300);

  Future<void> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ReviewScreen(review: sixMeasures())));
  }

  double scrolled(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: page, matching: find.byType(Scrollable)).first,
      )
      .position
      .pixels;

  Future<void> startReplay(WidgetTester tester) async {
    final play = find.byKey(const Key('review_play_button'));
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pump();
    await tester.pump(fallback);
  }

  /// Lets the replay run on for [seconds], and the screen catch up.
  Future<void> playOn(WidgetTester tester, int seconds) async {
    await tester.pump(Duration(seconds: seconds));
    await tester.pump(scrollTime);
  }

  bool playheadIn(WidgetTester tester, int timelineMeasure) =>
      tester
          .widget<StaffNotationView>(find.byKey(Key('review_measure_$timelineMeasure')))
          .playheadUnits !=
      null;

  testWidgets('The replay keeps the measure being played on screen', (tester) async {
    await pumpReview(tester);
    await startReplay(tester);

    await playOn(tester, 9); // into measure 2
    final atMeasure2 = scrolled(tester);
    await playOn(tester, 8); // into measure 4
    expect(scrolled(tester), greaterThan(atMeasure2));
  });

  testWidgets('Scrolling up during a replay stops it following, and the replay plays on', (
    tester,
  ) async {
    await pumpReview(tester);
    await startReplay(tester);
    await playOn(tester, 9); // into measure 2
    final atMeasure2 = scrolled(tester);

    // The player drags the screen down, to look back up the run.
    await tester.drag(page, const Offset(0, 150));
    await tester.pump(scrollTime);
    final lookingBack = scrolled(tester);
    expect(lookingBack, lessThan(atMeasure2));

    await playOn(tester, 8); // into measure 4
    expect(scrolled(tester), lookingBack, reason: 'left where the player put it');
    expect(find.byKey(const Key('review_stop_button')), findsOneWidget, reason: 'still replaying');
    expect(playheadIn(tester, 4), isTrue);

    // The next replay follows again.
    final stop = find.byKey(const Key('review_stop_button'));
    await tester.ensureVisible(stop);
    await tester.pump(scrollTime);
    await tester.tap(stop);
    await tester.pump();
    final beforeNextReplay = scrolled(tester);
    await tester.tap(find.byKey(const Key('review_play_button')));
    await tester.pump();
    await tester.pump(fallback);
    await playOn(tester, 17); // into measure 4
    expect(scrolled(tester), isNot(beforeNextReplay));
  });

  testWidgets('Scrolling further down during a replay does not stop it following', (tester) async {
    await pumpReview(tester);
    await startReplay(tester);
    await playOn(tester, 5); // into measure 1

    await tester.drag(page, const Offset(0, -100));
    await tester.pump(scrollTime);
    final afterDrag = scrolled(tester);

    await playOn(tester, 12); // into measure 4
    expect(scrolled(tester), greaterThan(afterDrag));
  });
}
