import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';
import 'package:snare_drum_score_app/services/app_settings.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/widgets/confetti.dart';
import 'package:snare_drum_score_app/widgets/judgement_style.dart';
import 'package:snare_drum_score_app/widgets/mic_light.dart';
import 'package:snare_drum_score_app/widgets/settings_scope.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';
import 'package:snare_drum_score_app/widgets/tempo_mark.dart';
import 'package:snare_drum_score_app/widgets/timing_needle.dart';

import 'support/fake_history.dart';
import 'support/fake_mic.dart';
import 'support/fake_screen_awake.dart';
import 'support/synth_audio.dart';

void main() {
  /// The tempo mark inside [finder], as (beat note, BPM).
  (TempoBeat, int) markIn(WidgetTester tester, Finder finder) {
    final mark = tester.widget<TempoMark>(
      find.descendant(of: finder, matching: find.byType(TempoMark), matchRoot: true),
    );
    return (mark.beat, mark.bpm);
  }

  /// The practice tempo shown beside the stepper.
  (TempoBeat, int) tempoShown(WidgetTester tester) =>
      markIn(tester, find.byKey(const Key('practice_tempo_value')));

  Future<void> pumpPractice(
    WidgetTester tester, {
    int tempoBpm = 60,
    RhythmScore? score,
    FakeMicInput? mic,
    FakeMicLatencyStore? latencyStore,
    FakeMicCalibrationStore? calibrationStore,
    AppSettings? settings,
    String? scoreId,
    InMemoryPracticeHistoryStore? historyStore,
    FakeScreenAwake? screenAwake,
  }) async {
    score ??= RhythmScore.empty(title: 'Practice Test', tempoBpm: tempoBpm);
    mic ??= FakeMicInput();
    final appSettings = settings ?? AppSettings();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SettingsScope(settings: appSettings, child: child!),
        home: PracticeScreen(
          score: score,
          createMicInput: () => mic!,
          latencyStore: latencyStore ?? FakeMicLatencyStore(),
          calibrationStore: calibrationStore ?? FakeMicCalibrationStore(),
          scoreId: scoreId,
          historyStore: historyStore,
          screenAwake: screenAwake ?? FakeScreenAwake(),
        ),
      ),
    );
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

  testWidgets('Idle state shows the count-in, first 2 measures, and a Start button', (
    tester,
  ) async {
    await pumpPractice(tester);

    expect(find.text('Count-in'), findsOneWidget);
    expect(find.text('Measure 1'), findsOneWidget);
    expect(find.text('Measure 2'), findsOneWidget);
    expect(find.byKey(const Key('practice_start_button')), findsOneWidget);
    expect(tempoShown(tester), (TempoBeat.quarter, 60));
  });

  testWidgets('Tempo stepper adjusts the practice tempo while idle', (tester) async {
    await pumpPractice(tester);

    await tester.tap(find.byKey(const Key('practice_tempo_increase')));
    await tester.pump();
    expect(tempoShown(tester), (TempoBeat.quarter, 65));

    await tester.tap(find.byKey(const Key('practice_tempo_decrease')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('practice_tempo_decrease')));
    await tester.pump();
    expect(tempoShown(tester), (TempoBeat.quarter, 55));
  });

  testWidgets(
    'Starting counts in, then transitions into Measure 1 and refreshes a slot 2 measures ahead',
    (tester) async {
      // At 60 BPM: 1s/quarter note, count-in measure = 4s, 9-measure timeline = 36s total.
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
    },
  );

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

  testWidgets('Finishing the whole timeline shows Done and allows practicing again', (
    tester,
  ) async {
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

  testWidgets(
    'Rhythm sound toggle defaults off and is togglable while idle; the settings are hidden '
    'during a run and come back as they were',
    (tester) async {
      await pumpPractice(tester);

      final toggleFinder = find.byKey(const Key('practice_rhythm_sound_toggle'));
      expect(tester.widget<SwitchListTile>(toggleFinder).value, isFalse);

      await tester.tap(toggleFinder);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggleFinder).value, isTrue);

      await tapButton(tester, const Key('practice_start_button'));
      await tester.pump();
      expect(toggleFinder, findsNothing);
      expect(find.byKey(const Key('practice_tempo_increase')), findsNothing);

      await tapButton(tester, const Key('practice_stop_button'));
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggleFinder).value, isTrue);
      expect(tempoShown(tester), (TempoBeat.quarter, 60));
    },
  );

  testWidgets('Measures in different meters each last their own length in a run', (tester) async {
    // 60 BPM: count-in and measure 1 in 2/4 (2s each), measure 2 in 3/4
    // (3s), measure 3 back in 2/4.
    final score = RhythmScore(
      title: 'Mixed',
      tempoBpm: 60,
      measures: [
        Measure.empty(meter: const TimeSignature(2, 4)),
        Measure.empty(meter: const TimeSignature(3, 4)),
        Measure.empty(meter: const TimeSignature(2, 4)),
      ],
    );
    await pumpPractice(tester, score: score);
    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);

    // The count-in follows measure 1's 2/4: Measure 1 starts after 2s.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Get ready...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Playing'), findsOneWidget);

    // 2s + 2s + 3s + 2s = 9s for the whole run.
    await tester.pump(const Duration(milliseconds: 6800));
    expect(find.text('Playing'), findsOneWidget, reason: 'measure 3 is still going');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('A 6/8 score counts in six eighth notes', (tester) async {
    // At 60 BPM an eighth note lasts half a second: the count-in is 3s.
    final score = RhythmScore.empty(
      title: 'Six Eight',
      tempoBpm: 60,
      meter: const TimeSignature(6, 8),
    );
    await pumpPractice(tester, score: score);

    final countIn = tester
        .widget<StaffNotationView>(
          find.descendant(
            of: find.byKey(const Key('practice_slot_a')),
            matching: find.byType(StaffNotationView),
          ),
        )
        .measure;
    expect(countIn.events.length, 6);
    expect(countIn.events.every((e) => e.value == NoteValue.eighth), isTrue);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('Get ready...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Playing'), findsOneWidget);
  });

  group("The tempo counts the score's beat note", () {
    // 4/4 at 60 BPM: the count-in is four quarter notes long.
    const cases = [
      (TempoBeat.half, 2000), // a quarter note is half a second
      (TempoBeat.eighth, 8000), // a quarter note is two seconds
      (TempoBeat.dottedQuarter, 2667), // 90 quarter notes a minute
    ];
    for (final (beat, countInMs) in cases) {
      testWidgets('${beat.label} notes', (tester) async {
        final score = RhythmScore.empty(title: 'Beat', tempoBpm: 60, tempoBeat: beat);
        await pumpPractice(tester, score: score);
        expect(tempoShown(tester), (beat, 60), reason: 'shown as its note = 60');

        await tapButton(tester, const Key('practice_start_button'));
        await tester.pump();
        await tester.pump(fallbackDelay);
        await tester.pump(Duration(milliseconds: countInMs - 150));
        expect(find.text('Get ready...'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Playing'), findsOneWidget);
      });
    }

    testWidgets('and the practice tempo steps in it', (tester) async {
      final score = RhythmScore.empty(title: 'Beat', tempoBpm: 150, tempoBeat: TempoBeat.half);
      await pumpPractice(tester, score: score);
      await tapButton(tester, const Key('practice_tempo_decrease'));
      await tester.pump();
      expect(tempoShown(tester), (TempoBeat.half, 145));
    });
  });

  group('On a phone-sized screen, a run shows everything without scrolling', () {
    // Logical sizes of real phones, app bar included in the height: a
    // Pixel 10-class phone, and a smaller one.
    for (final size in const [Size(412, 860), Size(360, 700)]) {
      testWidgets('${size.width.round()}x${size.height.round()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await pumpPractice(tester);

        await tapButton(tester, const Key('practice_start_button'));
        await tester.pump();
        await tester.pump(fallbackDelay);

        final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scrollable.position.maxScrollExtent, 0, reason: 'nothing to scroll to');
        // The judgement strip and all three measures sit inside the screen.
        for (final key in const [
          Key('practice_status_text'),
          Key('practice_slot_a'),
          Key('practice_slot_b'),
          Key('practice_slot_c'),
          Key('practice_stop_button'),
        ]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$key');
          expect(rect.bottom, lessThanOrEqualTo(size.height), reason: '$key');
        }
      });
    }
  });

  group('On a phone-sized screen, Start is in view without scrolling', () {
    for (final size in const [Size(412, 860), Size(360, 700)]) {
      testWidgets('${size.width.round()}x${size.height.round()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await pumpPractice(tester);

        final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
        expect(scrollable.position.maxScrollExtent, 0, reason: 'nothing to scroll to');
        for (final key in const [
          Key('practice_status_text'),
          Key('practice_tempo_value'),
          Key('practice_rhythm_sound_toggle'),
          Key('practice_slot_a'),
          Key('practice_slot_b'),
          Key('practice_slot_c'),
          Key('practice_start_button'),
        ]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$key');
          expect(rect.bottom, lessThanOrEqualTo(size.height), reason: '$key');
        }
      });
    }
  });

  testWidgets('The screen is kept on while practice is open, and let go on leaving', (
    tester,
  ) async {
    final screen = FakeScreenAwake();
    await pumpPractice(tester, screenAwake: screen);
    expect(screen.keptOn, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(screen.keptOn, isFalse);
  });

  testWidgets('After a run that was not judged, going faster is offered but not suggested', (
    tester,
  ) async {
    await pumpPractice(tester, tempoBpm: 60);
    await tester.tap(find.byKey(const Key('practice_rhythm_sound_toggle')));
    await tester.pump();

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const Key('practice_ready_faster')), findsNothing);
    expect(markIn(tester, find.byKey(const Key('practice_again_faster_button'))), (
      TempoBeat.quarter,
      65,
    ));
    expect(tester.widget(find.byKey(const Key('practice_again_button'))), isA<ElevatedButton>());
  });

  testWidgets('At the fastest tempo there is no going faster', (tester) async {
    await pumpPractice(tester, tempoBpm: 300);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(const Key('practice_again_button')), findsOneWidget);
    expect(find.byKey(const Key('practice_again_faster_button')), findsNothing);
  });

  testWidgets('A half-note-beat meter (3/2) keeps the count-in the same length as a real measure', (
    tester,
  ) async {
    // 3 half-note beats * 2s per half note (60 BPM) = 6s. A beat-unit bug
    // that spaced count-in clicks as if every beat were a quarter note would
    // finish the count-in after only 3s.
    final score = RhythmScore.empty(
      title: 'Three Two Practice',
      tempoBpm: 60,
      meter: const TimeSignature(3, 2),
    );
    await pumpPractice(tester, score: score);

    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);

    await tester.pump(const Duration(milliseconds: 5500));
    expect(find.text('Get ready...'), findsOneWidget, reason: 'count-in should not be done yet');

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Playing'), findsOneWidget);
  });

  group('Judging', () {
    // 60 BPM in 4/4: count-in clicks at 0-3s, then one measure of four
    // quarter notes at 4, 5, 6 and 7s.
    RhythmScore fourQuarters() {
      var measure = Measure.empty();
      for (var i = 0; i < 4; i++) {
        measure = measure.appendEvent(const RhythmEvent(NoteValue.quarter, EventType.normal));
      }
      return RhythmScore.empty(title: 'Judged', tempoBpm: 60).copyWithMeasure(0, measure);
    }

    // The microphone opens when Start is tapped; with no real audio in a
    // test, the timeline starts a second later (the fallback delay). The
    // count-in is then "heard" a further 100ms on -- standing in for the
    // phone's sound delay -- so timeline zero is 1.1s into the recording.
    const soundDelay = 0.1;
    const timelineStart = 1.0 + soundDelay;
    const clickTimes = [0.0, 1.0, 2.0, 3.0];
    Int16List recordingOf(List<double> timelineTimes) => synthRecording(
      seconds: 10,
      hitTimes: [for (final time in timelineTimes) timelineStart + time],
    );
    // The player's hits: on time, 60ms late, 110ms late, and the fourth
    // note not played at all.
    final recording = recordingOf([...clickTimes, 4.0, 5.06, 6.11]);

    Future<void> startRun(WidgetTester tester) async {
      await tapButton(tester, const Key('practice_start_button'));
      await tester.pump();
      await tester.pump(fallbackDelay);
    }

    /// Delivers [recording] to the microphone the way a real one would: in
    /// 100ms chunks, each arriving as time reaches it -- the screen works
    /// out when the recording began from when its audio arrives. Call after
    /// [startRun]; [toTimeline] is how far to play, in timeline seconds.
    var heardSeconds = 0.0;
    var elapsedSeconds = 0.0;
    setUp(() {
      heardSeconds = 0;
      elapsedSeconds = fallbackDelay.inMilliseconds / 1000; // spent in startRun
    });
    Future<void> hearUntil(
      WidgetTester tester,
      FakeMicInput mic,
      Int16List recording,
      double toTimeline,
    ) async {
      const step = 0.1;
      while (heardSeconds < timelineStart + toTimeline - 1e-9) {
        if (heardSeconds + step > elapsedSeconds + 1e-9) {
          await tester.pump(const Duration(milliseconds: 100));
          elapsedSeconds += step;
        }
        mic.hear(synthSlice(recording, heardSeconds, heardSeconds + step));
        heardSeconds += step;
      }
      await tester.pump();
    }

    List<StaffMark> marksIn(WidgetTester tester, String slotLabel) {
      final slot = find.ancestor(of: find.text(slotLabel), matching: find.byType(Column)).first;
      return tester
          .widget<StaffNotationView>(
            find.descendant(of: slot, matching: find.byType(StaffNotationView)),
          )
          .marks;
    }

    testWidgets('Each hit shows its judgement at the top, then the run ends with a tally', (
      tester,
    ) async {
      final mic = FakeMicInput();
      final store = FakeMicLatencyStore();
      await pumpPractice(tester, score: fourQuarters(), mic: mic, latencyStore: store);
      await startRun(tester);
      expect(mic.started, isTrue);

      await hearUntil(tester, mic, recording, 3.7);
      for (final label in ['Perfect', 'Great', 'Good', 'Miss']) {
        expect(
          find.textContaining(label),
          findsNothing,
          reason: 'nothing judged during the count-in',
        );
      }

      await hearUntil(tester, mic, recording, 4.5);
      expect(find.text('Perfect'), findsOneWidget);

      // The two late hits are marked "+".
      await hearUntil(tester, mic, recording, 5.5);
      expect(find.text('Great+'), findsOneWidget);
      expect(find.text('Perfect'), findsNothing);

      await hearUntil(tester, mic, recording, 6.5);
      expect(find.text('Good+'), findsOneWidget);

      await hearUntil(tester, mic, recording, 7.7);
      expect(find.text('Miss'), findsOneWidget);

      // The judgement sits above everything else on the screen.
      expect(
        tester.getTopLeft(find.text('Miss')).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('practice_status_text'))).dy),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1)); // rest of the timeline
      await tester.pump(const Duration(milliseconds: 500)); // judging settles shortly after
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Perfect 1  ·  Great 1  ·  Good 1  ·  Miss 1  ·  Fail 0'), findsOneWidget);
      expect(mic.stopped, isTrue);

      // Hearing the count-in measured this "phone's" sound delay, which is
      // reported and remembered for later runs.
      expect(find.textContaining('Count-in heard. Sound delay'), findsOneWidget);
      expect(store.history.measurements.single, closeTo(soundDelay, 0.01));
    });

    testWidgets('A finished judged run can be reviewed', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await hearUntil(tester, mic, recording, 7.7);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      await tapButton(tester, const Key('practice_review_button'));
      await tester.pumpAndSettle();

      expect(find.text('Review: Judged'), findsOneWidget);
      expect(find.text('Perfect 1  ·  Great 1  ·  Good 1  ·  Miss 1  ·  Fail 0'), findsOneWidget);
      // The two late hits, worst first.
      expect(find.textContaining('Measure 1, note 3: Good+'), findsOneWidget);
      expect(find.textContaining('Measure 1, note 2: Great+'), findsOneWidget);
      expect(find.text('Measure 1, note 4'), findsOneWidget, reason: 'the note not played');
      final marks = tester
          .widget<StaffNotationView>(find.byKey(const Key('review_measure_1')))
          .marks;
      expect(marks.length, 4);
      expect(marks[1].label, matches(RegExp(r'^\+(5[2-9]|6[0-8])$')), reason: '~60ms late');
    });

    testWidgets('A finished judged run is saved to its track\'s practice history, with a note', (
      tester,
    ) async {
      final mic = FakeMicInput();
      final history = InMemoryPracticeHistoryStore();
      await pumpPractice(
        tester,
        score: fourQuarters(),
        mic: mic,
        scoreId: 'Judged_1',
        historyStore: history,
      );
      await startRun(tester);
      await hearUntil(tester, mic, recording, 7.7);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      // Perfect, Great, Good and a Miss: (100 + 75 + 50 + 0) / 4 = 56%.
      expect(find.textContaining('Accuracy 56%'), findsOneWidget);

      final run = (await history.runsFor('Judged_1')).single;
      expect(run.tempoBpm, 60);
      expect(run.accuracy, closeTo(0.5625, 1e-9));
      final review = await history.loadReview(run);
      expect(review.judgements.length, 4, reason: 'the whole analysis is kept for review');

      await tapButton(tester, const Key('practice_note_button'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('run_note_field')), 'felt rushed');
      await tester.tap(find.byKey(const Key('run_note_save')));
      await tester.pumpAndSettle();

      expect((await history.runsFor('Judged_1')).single.note, 'felt rushed');
      expect(find.text('Edit note'), findsOneWidget);
    });

    testWidgets('Practice with no track to save to offers no note', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await hearUntil(tester, mic, recording, 7.7);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('practice_review_button')), findsOneWidget);
      expect(find.byKey(const Key('practice_note_button')), findsNothing);
      expect(find.textContaining('Accuracy 56%'), findsOneWidget);
    });

    testWidgets('A run that was not judged has nothing to review', (tester) async {
      final mic = FakeMicInput()..permissionGranted = false;
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(const Key('practice_review_button')), findsNothing);
    });

    testWidgets('A Great or Good says which way the hit was off: - early, + late', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      // 60ms early, 100ms early, 20ms early, then 20ms late.
      final earlyRecording = recordingOf([...clickTimes, 3.94, 4.9, 5.98, 7.02]);

      await hearUntil(tester, mic, earlyRecording, 4.5);
      expect(find.text('Great-'), findsOneWidget);

      await hearUntil(tester, mic, earlyRecording, 5.5);
      expect(find.text('Good-'), findsOneWidget);

      // A Perfect carries no sign, whichever side of the note it fell.
      await hearUntil(tester, mic, earlyRecording, 6.5);
      expect(find.text('Perfect'), findsOneWidget);
      await hearUntil(tester, mic, earlyRecording, 7.5);
      expect(find.text('Perfect'), findsOneWidget);

      // The tally stays one count per judgement, early and late together.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Perfect 2  ·  Great 1  ·  Good 1  ·  Miss 0  ·  Fail 0'), findsOneWidget);
    });

    testWidgets('The timing needle shows each hit early or late, a missed note not at all', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      expect(find.byKey(const Key('practice_timing_needle')), findsNothing, reason: 'idle');
      await startRun(tester);
      List<JudgedHit> needleHits() =>
          tester.widget<TimingNeedle>(find.byKey(const Key('practice_timing_needle'))).hits;
      expect(needleHits(), isEmpty);

      // 60ms early, 100ms early, 20ms early, then 20ms late.
      final earlyRecording = recordingOf([...clickTimes, 3.94, 4.9, 5.98, 7.02]);
      await hearUntil(tester, mic, earlyRecording, 5.5);
      expect([for (final hit in needleHits()) hit.judgement], [Judgement.great, Judgement.good]);
      for (final hit in needleHits()) {
        expect(TimingNeedle.positionOf(hit.offsetSeconds!), lessThan(0.5), reason: 'early');
      }

      await hearUntil(tester, mic, earlyRecording, 7.5);
      expect(needleHits(), hasLength(4));
      expect(TimingNeedle.positionOf(needleHits().last.offsetSeconds!), greaterThan(0.5));
    });

    testWidgets('A missed note leaves no tick on the needle', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);

      await hearUntil(tester, mic, recording, 7.7);
      expect(find.text('Miss'), findsOneWidget);
      final hits = tester
          .widget<TimingNeedle>(find.byKey(const Key('practice_timing_needle')))
          .hits;
      expect([for (final hit in hits) hit.noteIndex], [0, 1, 2]);
    });

    testWidgets('The mic light flashes for every hit heard, the count-in included', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      MicLight light() => tester.widget<MicLight>(find.byKey(const Key('practice_mic_light')));
      expect(light().listening, isFalse, reason: 'the microphone is off while idle');

      await startRun(tester);
      expect(light().listening, isTrue);
      expect(light().heardCount, 0);

      // The four count-in clicks, though nothing is judged yet.
      await hearUntil(tester, mic, recording, 3.7);
      expect(light().heardCount, 4);

      await hearUntil(tester, mic, recording, 6.5);
      expect(light().heardCount, 7);

      await tapButton(tester, const Key('practice_stop_button'));
      await tester.pump();
      expect(light().listening, isFalse);
    });

    Future<void> finishRun(WidgetTester tester, FakeMicInput mic, Int16List recording) async {
      await hearUntil(tester, mic, recording, 7.7);
      await tester.pumpAndSettle(const Duration(seconds: 1)); // rest of the timeline
      await tester.pump(const Duration(milliseconds: 500)); // judging settles shortly after
      expect(find.text('Done'), findsOneWidget);
    }

    testWidgets('A strong run suggests going faster, and one tap starts the next run 5 BPM up', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.0]));

      final ready = find.byKey(const Key('practice_ready_faster'));
      expect(find.descendant(of: ready, matching: find.text('100%. Ready for ')), findsOneWidget);
      expect(markIn(tester, ready), (TempoBeat.quarter, 65));
      final faster = find.byKey(const Key('practice_again_faster_button'));
      expect(find.descendant(of: faster, matching: find.text('Again at ')), findsOneWidget);
      expect(markIn(tester, faster), (TempoBeat.quarter, 65));
      // Going faster is the main button; the same tempo again is not.
      expect(tester.widget(faster), isA<ElevatedButton>());
      expect(tester.widget(find.byKey(const Key('practice_again_button'))), isA<OutlinedButton>());

      await tapButton(tester, const Key('practice_again_faster_button'));
      await tester.pump();
      await tester.pump(fallbackDelay);
      expect(find.byKey(const Key('practice_stop_button')), findsOneWidget, reason: 'running');

      await tapButton(tester, const Key('practice_stop_button'));
      await tester.pump();
      expect(tempoShown(tester), (TempoBeat.quarter, 65));
    });

    testWidgets('A weaker run still offers going faster, but Practice Again is the main button', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await finishRun(tester, mic, recording); // Perfect, Great, Good, Miss: 56%

      expect(find.byKey(const Key('practice_ready_faster')), findsNothing);
      expect(tester.widget(find.byKey(const Key('practice_again_button'))), isA<ElevatedButton>());
      expect(
        tester.widget(find.byKey(const Key('practice_again_faster_button'))),
        isA<OutlinedButton>(),
      );
    });

    testWidgets('A run with dynamics says after it how many were played as marked', (tester) async {
      final mic = FakeMicInput();
      // p from the first note, f from the third -- played all at one level.
      var measure = fourQuarters().measures.first;
      for (final (index, mark) in [(0, DynamicMark.p), (2, DynamicMark.f)]) {
        measure = measure.replaceAt(index, measure.events[index].copyWith(dynamicMark: mark));
      }
      await pumpPractice(tester, score: fourQuarters().copyWithMeasure(0, measure), mic: mic);
      await startRun(tester);
      expect(find.byKey(const Key('practice_dynamics_summary')), findsNothing);

      await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.0]));

      expect(find.text('0 of 1 dynamics as marked -- see Review'), findsOneWidget);
    });

    testWidgets('A run without dynamics says nothing about them', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.0]));
      expect(find.byKey(const Key('practice_dynamics_summary')), findsNothing);
    });

    group('Confetti', () {
      Finder confetti() => find.byType(ConfettiBurst);

      testWidgets('falls after a run that is all Perfect -- the bigger burst', (tester) async {
        final mic = FakeMicInput();
        await pumpPractice(tester, score: fourQuarters(), mic: mic);
        await startRun(tester);
        expect(confetti(), findsNothing);
        await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.0]));
        expect(tester.widget<ConfettiBurst>(confetti()).perfect, isTrue);
      });

      testWidgets('falls after a run above 90%, not all Perfect', (tester) async {
        final mic = FakeMicInput();
        await pumpPractice(tester, score: fourQuarters(), mic: mic);
        await startRun(tester);
        // Three Perfect and a Great: 94%.
        await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.06]));
        expect(tester.widget<ConfettiBurst>(confetti()).perfect, isFalse);

        // And not again once practising again.
        await tapButton(tester, const Key('practice_again_button'));
        await tester.pump();
        expect(confetti(), findsNothing);
      });

      testWidgets('not after a weaker run', (tester) async {
        final mic = FakeMicInput();
        await pumpPractice(tester, score: fourQuarters(), mic: mic);
        await startRun(tester);
        await finishRun(tester, mic, recording); // 56%
        expect(confetti(), findsNothing);
      });

      testWidgets('not when turned off in Settings', (tester) async {
        final mic = FakeMicInput();
        await pumpPractice(
          tester,
          score: fourQuarters(),
          mic: mic,
          settings: AppSettings()..confetti = false,
        );
        await startRun(tester);
        await finishRun(tester, mic, recordingOf([...clickTimes, 4.0, 5.0, 6.0, 7.0]));
        expect(confetti(), findsNothing);
      });
    });

    testWidgets('Playing during a rest shows Fail, marked in its own colour, outside the tally', (
      tester,
    ) async {
      // Measure 1: quarter note, quarter rest, quarter note, quarter rest --
      // notes at 4s and 6s, rests from 5-6s and 7-8s.
      var measure = Measure.empty();
      for (final type in [EventType.normal, EventType.rest, EventType.normal, EventType.rest]) {
        measure = measure.appendEvent(RhythmEvent(NoteValue.quarter, type));
      }
      final score = RhythmScore.empty(title: 'Rests', tempoBpm: 60).copyWithMeasure(0, measure);
      // Both notes on time, plus a hit in the middle of each rest.
      final restRecording = recordingOf([...clickTimes, 4.0, 5.5, 6.0, 7.5]);
      final mic = FakeMicInput();
      await pumpPractice(tester, score: score, mic: mic);
      await startRun(tester);

      await hearUntil(tester, mic, restRecording, 5.8);
      expect(find.text('Fail'), findsOneWidget);

      await hearUntil(tester, mic, restRecording, 6.4);
      expect(find.text('Perfect'), findsOneWidget);

      await hearUntil(tester, mic, restRecording, 7.8);
      expect(find.text('Fail'), findsOneWidget);

      final marks = marksIn(tester, 'Measure 1');
      expect(marks.length, 4);
      final failMarks = marks.where((m) => m.units > 13 && m.units < 23 || m.units > 37);
      expect(failMarks.length, 2);
      expect(failMarks.map((m) => m.color).toSet().length, 1);
      final failColor = failMarks.first.color;
      expect(failColor, isNot(Colors.red.shade700), reason: 'must read apart from Miss');

      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      // Two notes, two Perfects -- and the two fails on top.
      expect(find.text('Perfect 2  ·  Great 0  ·  Good 0  ·  Miss 0  ·  Fail 2'), findsOneWidget);
    });

    testWidgets('With "colour notes by judgement" on, notes take their colour as they are judged', (
      tester,
    ) async {
      final mic = FakeMicInput();
      final settings = AppSettings()..colorNotesByJudgement = true;
      await pumpPractice(tester, score: fourQuarters(), mic: mic, settings: settings);
      await startRun(tester);
      Map<int, Color> colorsOfMeasure1() => tester
          .widget<StaffNotationView>(
            find.descendant(
              of: find.ancestor(of: find.text('Measure 1'), matching: find.byType(Column)).first,
              matching: find.byType(StaffNotationView),
            ),
          )
          .eventColors;

      await hearUntil(tester, mic, recording, 3.7);
      expect(colorsOfMeasure1(), isEmpty, reason: 'nothing judged yet');

      await hearUntil(tester, mic, recording, 4.5);
      expect(colorsOfMeasure1(), {0: judgementColor(Judgement.perfect)});

      await hearUntil(tester, mic, recording, 7.7);
      expect(colorsOfMeasure1(), {
        0: judgementColor(Judgement.perfect),
        1: judgementColor(Judgement.great),
        2: judgementColor(Judgement.good),
        3: judgementColor(Judgement.miss),
      });
    });

    testWidgets('With the mode off (the default), notes stay black', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);

      await hearUntil(tester, mic, recording, 7.7);

      final staffs = tester.widgetList<StaffNotationView>(find.byType(StaffNotationView));
      expect(staffs.every((staff) => staff.eventColors.isEmpty), isTrue);
    });

    testWidgets('Each hit is marked under the staff where it landed', (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);

      await hearUntil(tester, mic, recording, 3.7);
      expect(marksIn(tester, 'Count-in'), isEmpty, reason: 'count-in clicks are not hits');
      expect(marksIn(tester, 'Measure 1'), isEmpty);

      await hearUntil(tester, mic, recording, 7.7);
      final marks = marksIn(tester, 'Measure 1');

      // At 60 BPM a unit is 1/12s, and the notes are at units 0, 12, 24, 36.
      expect(marks.length, 4);
      expect(marks[0].units, closeTo(0, 0.1)); // on time
      expect(marks[1].units, closeTo(12 + 0.06 * 12, 0.1)); // 60ms late
      expect(marks[2].units, closeTo(24 + 0.11 * 12, 0.1)); // 110ms late
      expect(marks[3].units, closeTo(36, 1e-9)); // not played: marked at the note
      expect(marks.map((m) => m.isAbsence), [false, false, false, true]);
      // Each judgement has its own colour.
      expect(marks.map((m) => m.color).toSet().length, 4);
    });

    testWidgets('A run with the rhythm sound on is not judged and never opens the microphone', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);

      await tester.tap(find.byKey(const Key('practice_rhythm_sound_toggle')));
      await tester.pump();
      await startRun(tester);

      expect(mic.started, isFalse);
      expect(find.byKey(const Key('practice_judging_notice')), findsNothing);
    });

    testWidgets('Without microphone permission the run still starts, and says it is not judged', (
      tester,
    ) async {
      final mic = FakeMicInput()..permissionGranted = false;
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);

      expect(mic.started, isFalse);
      expect(find.text('Get ready...'), findsOneWidget);
      expect(find.text('Microphone unavailable. This run is not judged.'), findsOneWidget);
    });

    // What the microphone hears when the count-in goes to headphones: only
    // the player, here playing every note on time.
    final recordingWithoutCountIn = recordingOf([4.0, 5.0, 6.0, 7.0]);

    testWidgets('Says so when the count-in never reaches the microphone', (tester) async {
      final mic = FakeMicInput();
      final store = FakeMicLatencyStore();
      await pumpPractice(tester, score: fourQuarters(), mic: mic, latencyStore: store);
      await startRun(tester);

      await hearUntil(tester, mic, recordingWithoutCountIn, 7.7);

      expect(find.text('Could not hear the count-in. This run is not judged.'), findsOneWidget);
      expect(find.text('Perfect'), findsNothing);
      expect(marksIn(tester, 'Measure 1'), isEmpty);
      expect(store.history.measurements, isEmpty);
    });

    testWidgets(
      'Once the sound delay is known from earlier runs, a run whose count-in is not heard '
      'is judged by estimate',
      (tester) async {
        final mic = FakeMicInput();
        final store = FakeMicLatencyStore([soundDelay, soundDelay, soundDelay]);
        await pumpPractice(tester, score: fourQuarters(), mic: mic, latencyStore: store);
        await startRun(tester);

        await hearUntil(tester, mic, recordingWithoutCountIn, 7.7);

        expect(find.text('Perfect'), findsOneWidget);
        expect(
          find.text('Count-in not heard. Timing estimated from earlier runs.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('practice_judging_notice')), findsNothing);
        expect(marksIn(tester, 'Measure 1').length, 4);

        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Perfect 4  ·  Great 0  ·  Good 0  ·  Miss 0  ·  Fail 0'), findsOneWidget);
        // An estimated run measures nothing, so it must not feed the history
        // it was estimated from.
        expect(store.history.measurements.length, 3);
      },
    );

    testWidgets('A saved calibration judges a run whose count-in is not heard, in place of the '
        'delay learned through the speaker', (tester) async {
      // Bluetooth headphones: the count-in never reaches the microphone, and
      // the player, following what they hear, lands 250ms behind the app's
      // clock -- far from the 100ms the speaker runs measured.
      const headphoneDelay = 0.25;
      final headphoneRecording = synthRecording(
        seconds: 10,
        hitTimes: [
          for (final time in [4.0, 5.0, 6.0, 7.0]) 1.0 + headphoneDelay + time,
        ],
      );
      final mic = FakeMicInput();
      final store = FakeMicLatencyStore([soundDelay, soundDelay, soundDelay]);
      await pumpPractice(
        tester,
        score: fourQuarters(),
        mic: mic,
        latencyStore: store,
        calibrationStore: FakeMicCalibrationStore(headphoneDelay),
      );
      await startRun(tester);

      await hearUntil(tester, mic, headphoneRecording, 7.9);

      expect(find.text('Perfect'), findsOneWidget);
      expect(find.text('Count-in not heard. Timing from your calibration.'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Perfect 4  ·  Great 0  ·  Good 0  ·  Miss 0  ·  Fail 0'), findsOneWidget);
    });

    testWidgets('A run that hears its count-in goes by the count-in, whatever the calibration', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(
        tester,
        score: fourQuarters(),
        mic: mic,
        // Calibrated on headphones, now practising on the speaker.
        calibrationStore: FakeMicCalibrationStore(0.25),
      );
      await startRun(tester);

      await hearUntil(tester, mic, recording, 4.5);

      expect(find.text('Perfect'), findsOneWidget);
      expect(find.byKey(const Key('practice_alignment_detail')), findsNothing);
    });

    testWidgets('Stopping a run releases the microphone and clears the judgement and marks', (
      tester,
    ) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await hearUntil(tester, mic, recording, 4.5);
      expect(find.text('Perfect'), findsOneWidget);

      await tapButton(tester, const Key('practice_stop_button'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(mic.stopped, isTrue);
      expect(find.text('Perfect'), findsNothing);
      expect(marksIn(tester, 'Measure 1'), isEmpty);
    });
  });
}
