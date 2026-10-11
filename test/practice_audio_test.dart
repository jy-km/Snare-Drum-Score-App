import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';

import 'support/fake_mic.dart';

// In a file of its own: the audio plugin sets itself up once per test run
// and remembers if that failed, which it does in every other test (no
// plugin). This test stands in for the plugin, so it has to be the first to
// use it.
void main() {
  const fallbackDelay = Duration(milliseconds: 1000);

  Future<void> pumpPractice(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticeScreen(
          score: RhythmScore.empty(title: 'Practice Test', tempoBpm: 60),
          createMicInput: FakeMicInput.new,
          latencyStore: FakeMicLatencyStore(),
          calibrationStore: FakeMicCalibrationStore(),
        ),
      ),
    );
  }

  Future<void> tapButton(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  testWidgets('Stop stops the run\'s audio, not just the playhead', (tester) async {
    // Stand in for the audio plugin, recording what the screen asks of it.
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if ((call.arguments as Map?)?['playerId'] == 'practice_click') calls.add(call.method);
      return null;
    });
    // The plugin's app-wide setup has to succeed before any player works.
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    const eventChannels = [
      EventChannel('xyz.luan/audioplayers/events/practice_click'),
      EventChannel('xyz.luan/audioplayers.global/events'),
    ];
    for (final channel in eventChannels) {
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), null);
      for (final channel in eventChannels) {
        messenger.setMockStreamHandler(channel, null);
      }
    });

    await pumpPractice(tester);
    await tester.tap(find.byKey(const Key('practice_rhythm_sound_toggle')));
    await tester.pump();
    await tapButton(tester, const Key('practice_start_button'));
    await tester.pump();
    await tester.pump(fallbackDelay);
    expect(calls, isNot(contains('stop')));

    await tapButton(tester, const Key('practice_stop_button'));
    await tester.pump();

    expect(calls, contains('stop'));
  });
}
