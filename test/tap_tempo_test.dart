import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/services/tap_tempo.dart';
import 'package:snare_drum_score_app/widgets/tempo_mark.dart';

import 'support/fake_mic.dart';
import 'support/fake_screen_awake.dart';

void main() {
  group('TapTempo', () {
    final start = DateTime(2026, 10, 24, 12);
    DateTime at(int ms) => start.add(Duration(milliseconds: ms));
    TapTempo tapper() => TapTempo(minBpm: 20, maxBpm: 300);

    test('The first tap has no tempo; from the second on, it is how often you tap', () {
      final taps = tapper();
      expect(taps.tap(at(0)), isNull);
      expect(taps.tap(at(500)), 120);
      expect(taps.tap(at(1000)), 120);
    });

    test('Unsteady taps are averaged over the last few', () {
      final taps = tapper();
      for (final ms in [0, 500, 1020, 1500]) {
        taps.tap(at(ms));
      }
      expect(taps.tap(at(2000)), 120, reason: 'gaps of 500, 520, 480 and 500ms');
    });

    test('A long pause starts afresh', () {
      final taps = tapper();
      taps.tap(at(0));
      taps.tap(at(500));
      expect(taps.tap(at(500 + 4000)), isNull);
      expect(taps.tap(at(500 + 4000 + 1000)), 60);
    });

    test('A clearly different gap is taken as a new tempo straight away', () {
      final taps = tapper();
      for (final ms in [0, 500, 1000, 1500]) {
        taps.tap(at(ms));
      }
      expect(taps.tap(at(2500)), 60, reason: 'a 1s gap after half-second ones');
      expect(taps.tap(at(3500)), 60);
    });

    test('Stays within the tempos the app allows', () {
      final fast = tapper();
      fast.tap(at(0));
      expect(fast.tap(at(100)), 300, reason: '600 taps a minute');

      final slow = tapper();
      slow.tap(at(0));
      expect(slow.tap(at(3000)), 20, reason: 'the slowest gap that still counts');
    });
  });

  /// Taps the button [count] times, [gap] apart.
  Future<void> tapBeat(WidgetTester tester, Key key, int count, Duration gap) async {
    for (var i = 0; i < count; i++) {
      if (i > 0) await tester.pump(gap);
      await tester.tap(find.byKey(key));
    }
    await tester.pump();
  }

  /// The practice tempo shown, as (beat note, BPM).
  (TempoBeat, int) shown(WidgetTester tester) {
    final mark = tester.widget<TempoMark>(find.byKey(const Key('practice_tempo_value')));
    return (mark.beat, mark.bpm);
  }

  Future<void> pumpPractice(WidgetTester tester, RhythmScore score) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeScreen(
          score: score,
          createMicInput: FakeMicInput.new,
          latencyStore: FakeMicLatencyStore(),
          calibrationStore: FakeMicCalibrationStore(),
          screenAwake: FakeScreenAwake(),
        ),
      ),
    );
  }

  testWidgets('Tapping sets the practice tempo', (tester) async {
    await pumpPractice(tester, RhythmScore.empty(title: 'Taps', tempoBpm: 60));

    await tapBeat(tester, const Key('practice_tap_tempo'), 4, const Duration(milliseconds: 400));

    expect(shown(tester), (TempoBeat.quarter, 150));
  });

  testWidgets('In a half-note-beat score, the taps are half notes', (tester) async {
    await pumpPractice(
      tester,
      RhythmScore.empty(title: 'Taps', tempoBpm: 60).copyWith(tempoBeat: TempoBeat.half),
    );

    await tapBeat(tester, const Key('practice_tap_tempo'), 3, const Duration(milliseconds: 500));

    expect(shown(tester), (TempoBeat.half, 120));
  });

  testWidgets('In a dotted-quarter score (6/8 felt in two), the taps are dotted quarters', (
    tester,
  ) async {
    await pumpPractice(
      tester,
      RhythmScore.empty(
        title: 'Taps',
        tempoBpm: 60,
      ).copyWith(tempoBeat: TempoBeat.dottedQuarter),
    );

    await tapBeat(tester, const Key('practice_tap_tempo'), 3, const Duration(milliseconds: 750));

    expect(shown(tester), (TempoBeat.dottedQuarter, 80));
  });

  testWidgets('Tapping sets the score tempo in the editor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(
          fileName: 'x',
          initialScore: RhythmScore.empty(title: 'Taps', tempoBpm: 60),
        ),
      ),
    );

    await tapBeat(tester, const Key('editor_tap_tempo'), 3, const Duration(milliseconds: 600));

    expect(tester.widget<TextField>(find.byKey(const Key('tempo_field'))).controller!.text, '100');
  });

  testWidgets('On a narrow phone, the tempo rows still fit', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpPractice(
      tester,
      RhythmScore.empty(title: 'Taps', tempoBpm: 300).copyWith(tempoBeat: TempoBeat.half),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(
          fileName: 'x',
          initialScore: RhythmScore.empty(title: 'Taps'),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
