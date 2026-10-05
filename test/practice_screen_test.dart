import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

import 'support/fake_mic.dart';
import 'support/synth_audio.dart';

void main() {
  Future<void> pumpPractice(
    WidgetTester tester, {
    int tempoBpm = 60,
    RhythmScore? score,
    FakeMicInput? mic,
    FakeMicLatencyStore? latencyStore,
    FakeMicCalibrationStore? calibrationStore,
  }) async {
    score ??= RhythmScore.empty(title: 'Practice Test', tempoBpm: tempoBpm);
    mic ??= FakeMicInput();
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeScreen(
          score: score,
          createMicInput: () => mic!,
          latencyStore: latencyStore ?? FakeMicLatencyStore(),
          calibrationStore: calibrationStore ?? FakeMicCalibrationStore(),
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

  testWidgets(
      'Rhythm sound toggle defaults off and is togglable while idle; the settings are hidden '
      'during a run and come back as they were', (tester) async {
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
    expect(find.text('60 BPM'), findsOneWidget);
  });

  testWidgets('Measures in different meters each last their own length in a run',
      (tester) async {
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

  testWidgets('A half-note-beat meter (3/2) keeps the count-in the same length as a real measure',
      (tester) async {
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

    testWidgets('Each hit shows its judgement at the top, then the run ends with a tally',
        (tester) async {
      final mic = FakeMicInput();
      final store = FakeMicLatencyStore();
      await pumpPractice(tester, score: fourQuarters(), mic: mic, latencyStore: store);
      await startRun(tester);
      expect(mic.started, isTrue);

      await hearUntil(tester, mic, recording, 3.7);
      for (final label in ['Perfect', 'Great', 'Good', 'Miss']) {
        expect(find.textContaining(label), findsNothing,
            reason: 'nothing judged during the count-in');
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

    testWidgets('A run that was not judged has nothing to review', (tester) async {
      final mic = FakeMicInput()..permissionGranted = false;
      await pumpPractice(tester, score: fourQuarters(), mic: mic);
      await startRun(tester);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(const Key('practice_review_button')), findsNothing);
    });

    testWidgets('A Great or Good says which way the hit was off: - early, + late',
        (tester) async {
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

    testWidgets('Playing during a rest shows Fail, marked in its own colour, outside the tally',
        (tester) async {
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
      expect(
        find.text('Perfect 2  ·  Great 0  ·  Good 0  ·  Miss 0  ·  Fail 2'),
        findsOneWidget,
      );
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

    testWidgets('A run with the rhythm sound on is not judged and never opens the microphone',
        (tester) async {
      final mic = FakeMicInput();
      await pumpPractice(tester, score: fourQuarters(), mic: mic);

      await tester.tap(find.byKey(const Key('practice_rhythm_sound_toggle')));
      await tester.pump();
      await startRun(tester);

      expect(mic.started, isFalse);
      expect(find.byKey(const Key('practice_judging_notice')), findsNothing);
    });

    testWidgets('Without microphone permission the run still starts, and says it is not judged',
        (tester) async {
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
        'is judged by estimate', (tester) async {
      final mic = FakeMicInput();
      final store = FakeMicLatencyStore([soundDelay, soundDelay, soundDelay]);
      await pumpPractice(tester, score: fourQuarters(), mic: mic, latencyStore: store);
      await startRun(tester);

      await hearUntil(tester, mic, recordingWithoutCountIn, 7.7);

      expect(find.text('Perfect'), findsOneWidget);
      expect(find.text('Count-in not heard. Timing estimated from earlier runs.'), findsOneWidget);
      expect(find.byKey(const Key('practice_judging_notice')), findsNothing);
      expect(marksIn(tester, 'Measure 1').length, 4);

      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Perfect 4  ·  Great 0  ·  Good 0  ·  Miss 0  ·  Fail 0'), findsOneWidget);
      // An estimated run measures nothing, so it must not feed the history
      // it was estimated from.
      expect(store.history.measurements.length, 3);
    });

    testWidgets(
        'A saved calibration judges a run whose count-in is not heard, in place of the '
        'delay learned through the speaker', (tester) async {
      // Bluetooth headphones: the count-in never reaches the microphone, and
      // the player, following what they hear, lands 250ms behind the app's
      // clock -- far from the 100ms the speaker runs measured.
      const headphoneDelay = 0.25;
      final headphoneRecording = synthRecording(
        seconds: 10,
        hitTimes: [for (final time in [4.0, 5.0, 6.0, 7.0]) 1.0 + headphoneDelay + time],
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

    testWidgets('A run that hears its count-in goes by the count-in, whatever the calibration',
        (tester) async {
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

    testWidgets('Stopping a run releases the microphone and clears the judgement and marks',
        (tester) async {
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
