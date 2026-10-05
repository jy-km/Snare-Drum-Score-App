import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/screens/calibration_screen.dart';

import 'support/fake_mic.dart';
import 'support/synth_audio.dart';

void main() {
  // With no real audio in a test, the beat starts a second after Start is
  // tapped (the screen's fallback delay), and the microphone opened at the
  // tap -- so the app's clock puts beat 0 at 1.0s into the recording.
  const beatStart = 1.0;
  const beat = 0.5; // 120 BPM
  const totalBeats = 20;

  /// What the microphone hears when the player hits every beat [offset]
  /// after the app's clock says it plays.
  Int16List playingAlong(double offset, {int fromBeat = 0}) => synthRecording(
        seconds: 13,
        hitTimes: [for (var i = fromBeat; i < totalBeats; i++) beatStart + offset + i * beat],
      );

  Future<void> pumpCalibration(
    WidgetTester tester,
    FakeMicInput mic,
    FakeMicCalibrationStore store,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CalibrationScreen(createMicInput: () => mic, store: store)),
    );
    await tester.pump();
  }

  /// Taps Start and plays [recording] to the microphone in real time, 100ms
  /// at a time, through the end of the run.
  Future<void> runCalibration(WidgetTester tester, FakeMicInput mic, Int16List recording) async {
    await tester.tap(find.byKey(const Key('calibration_start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    var elapsed = 1.0;
    for (var heard = 0.0; heard < 12.5; heard += 0.1) {
      if (heard + 0.1 > elapsed + 1e-9) {
        await tester.pump(const Duration(milliseconds: 100));
        elapsed += 0.1;
      }
      mic.hear(synthSlice(recording, heard, heard + 0.1));
    }
    await tester.pump();
  }

  testWidgets('Playing along measures the offset, shows it and saves it', (tester) async {
    final mic = FakeMicInput();
    final store = FakeMicCalibrationStore();
    await pumpCalibration(tester, mic, store);
    expect(find.text('Not calibrated yet.'), findsOneWidget);

    await runCalibration(tester, mic, playingAlong(0.18));

    expect(store.offsetSeconds, closeTo(0.18, 0.008));
    final shown = '${(store.offsetSeconds! * 1000).round()} ms';
    expect(find.text('Offset: $shown'), findsOneWidget);
    expect(find.text('Saved offset: $shown'), findsOneWidget);
    // 16 measured beats; the 4 settling-in beats before them don't count.
    expect(find.textContaining('Averaged over 16 hits'), findsOneWidget);
    expect(mic.stopped, isTrue);
  });

  testWidgets('A run with too few hits says so and keeps the previous calibration',
      (tester) async {
    final mic = FakeMicInput();
    final store = FakeMicCalibrationStore(0.12);
    await pumpCalibration(tester, mic, store);
    expect(find.text('Saved offset: 120 ms'), findsOneWidget);

    // The player only joins in for the last five beats.
    await runCalibration(tester, mic, playingAlong(0.18, fromBeat: 15));

    expect(find.textContaining('Only 5 hits were heard'), findsOneWidget);
    expect(find.textContaining('Nothing was saved'), findsOneWidget);
    expect(store.offsetSeconds, 0.12);
    expect(find.text('Saved offset: 120 ms'), findsOneWidget);
  });

  testWidgets('Clearing removes the saved calibration', (tester) async {
    final store = FakeMicCalibrationStore(0.12);
    await pumpCalibration(tester, FakeMicInput(), store);

    await tester.tap(find.byKey(const Key('calibration_clear_button')));
    await tester.pump();

    expect(store.offsetSeconds, isNull);
    expect(find.text('Not calibrated yet.'), findsOneWidget);
    expect(find.byKey(const Key('calibration_clear_button')), findsNothing);
  });

  testWidgets('Without microphone permission it explains instead of starting', (tester) async {
    final mic = FakeMicInput()..permissionGranted = false;
    await pumpCalibration(tester, mic, FakeMicCalibrationStore());

    await tester.tap(find.byKey(const Key('calibration_start_button')));
    await tester.pump();

    expect(find.textContaining('Microphone permission was denied'), findsOneWidget);
    expect(find.byKey(const Key('calibration_start_button')), findsOneWidget);
    expect(mic.started, isFalse);
  });

  testWidgets('Stopping partway saves nothing', (tester) async {
    final mic = FakeMicInput();
    final store = FakeMicCalibrationStore();
    await pumpCalibration(tester, mic, store);

    await tester.tap(find.byKey(const Key('calibration_start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.byKey(const Key('calibration_stop_button')));
    await tester.pump();

    expect(mic.stopped, isTrue);
    expect(store.offsetSeconds, isNull);
    expect(find.byKey(const Key('calibration_start_button')), findsOneWidget);
    expect(find.byKey(const Key('calibration_result')), findsNothing);
  });
}
