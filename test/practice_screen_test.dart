import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';

void main() {
  Future<void> pumpPractice(WidgetTester tester, {int tempoBpm = 60}) async {
    final score = RhythmScore.empty(title: 'Practice Test', tempoBpm: tempoBpm);
    await tester.pumpWidget(MaterialApp(home: PracticeScreen(score: score)));
  }

  // The action button sits below the count-in and 3 full-width stacked
  // measures inside a SingleChildScrollView, so it can scroll out of the
  // test viewport -- ensureVisible scrolls it back in before tapping.
  Future<void> tapButton(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  // Widget tests have no real audio platform channel, so the count-in never
  // gets a real position sample to calibrate against -- it falls back to
  // starting immediately after this delay (see PracticeScreen's
  // `_countInFallbackDelay`).
  const fallbackDelay = Duration(milliseconds: 1000);

  testWidgets('Idle state shows the count-in, first 2 measures, and a Start button', (tester) async {
    await pumpPractice(tester);

    expect(find.text('Count-in'), findsOneWidget);
    expect(find.text('Measure 1'), findsOneWidget);
    expect(find.text('Measure 2'), findsOneWidget);
    expect(find.byKey(const Key('practice_start_button')), findsOneWidget);
    expect(find.text('60 BPM'), findsOneWidget);
  });

  testWidgets('Tempo stepper adjusts the practice tempo while idle', (tester) async {
    await pumpPractice(tester);

    await tester.tap(find.byKey(const Key('practice_tempo_increase')));
    await tester.pump();
    expect(find.text('65 BPM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('practice_tempo_decrease')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('practice_tempo_decrease')));
    await tester.pump();
    expect(find.text('55 BPM'), findsOneWidget);
  });

  testWidgets(
      'Starting counts in, then transitions into Measure 1 and refreshes a slot 2 measures ahead',
      (tester) async {
    // At 60 BPM: 250ms/unit, count-in measure = 4s, 9-measure timeline = 36s total.
    await pumpPractice(tester, tempoBpm: 60);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay); // no audio channel in tests -> fallback starts the clock
    expect(find.text('Get ready...'), findsOneWidget);
    expect(find.byKey(const Key('practice_stop_button')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4)); // count-in measure elapses -> Measure 1 begins
    expect(find.text('Playing'), findsOneWidget);
    expect(find.text('Measure 3'), findsOneWidget); // slot refreshed 2 ahead
    expect(find.text('Measure 1'), findsOneWidget);
    expect(find.text('Measure 2'), findsOneWidget);
  });

  testWidgets('Stop returns to idle and resets the slots', (tester) async {
    await pumpPractice(tester, tempoBpm: 60);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Measure 3'), findsOneWidget);

    await tapButton(tester, const Key('practice_stop_button'));
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Count-in'), findsOneWidget);
    expect(find.text('Measure 1'), findsOneWidget);
    expect(find.text('Measure 2'), findsOneWidget);
    expect(find.byKey(const Key('practice_start_button')), findsOneWidget);
  });

  testWidgets('Finishing the whole timeline shows Done and allows practicing again', (tester) async {
    await pumpPractice(tester, tempoBpm: 60);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    await tester.pumpAndSettle(const Duration(seconds: 1)); // full timeline duration

    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const Key('practice_again_button')), findsOneWidget);

    await tapButton(tester, const Key('practice_again_button'));
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Count-in'), findsOneWidget);
  });
}
