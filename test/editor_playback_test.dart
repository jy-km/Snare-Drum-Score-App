import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/services/click_sound.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

// In a file of its own, like practice_audio_test.dart: this test stands in
// for the audio plugin, so it has to be the first to use it.
void main() {
  testWidgets('Test play ends by itself at the end of the track', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(ClickSound.preload);

    // Stand in for the audio plugin: it reports the sound as prepared, a
    // position that follows the clock, and -- like a snare still ringing --
    // never that the sound has finished.
    final calls = <String>[];
    DateTime? startedAt;
    MockStreamHandlerEventSink? playerEvents;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'setSourceBytes':
          playerEvents?.success({'event': 'audio.onPrepared', 'value': true});
        case 'stop':
          startedAt = null;
        case 'resume':
          startedAt = clock.now();
        case 'getCurrentPosition':
          final start = startedAt;
          return start == null ? 0 : clock.now().difference(start).inMilliseconds;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    const playerChannel = EventChannel('xyz.luan/audioplayers/events/rhythm_player');
    const globalChannel = EventChannel('xyz.luan/audioplayers.global/events');
    messenger.setMockStreamHandler(
      playerChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          playerEvents = events;
        },
      ),
    );
    messenger.setMockStreamHandler(
      globalChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), null);
      messenger.setMockStreamHandler(playerChannel, null);
      messenger.setMockStreamHandler(globalChannel, null);
    });

    // One 4/4 measure at 120 BPM: two seconds long.
    final score = RhythmScore.empty(title: 'Short', tempoBpm: 120, measuresCount: 1)
        .copyWithMeasure(
          0,
          Measure([
            for (var i = 0; i < 4; i++) const RhythmEvent(NoteValue.quarter, EventType.normal),
          ]),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(fileName: 'playback_test', initialScore: score),
      ),
    );

    StaffNotationView staff() =>
        tester.widget<StaffNotationView>(find.byKey(const Key('editor_staff')));
    Future<void> pumpFor(Duration time) async {
      for (
        var elapsed = Duration.zero;
        elapsed < time;
        elapsed += const Duration(milliseconds: 50)
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // The sound samples were loaded in real time (above), and a wait on them
    // only finishes in real time too -- so Play needs a moment of it before
    // the test's own clock takes over.
    Future<void> pressPlay() async {
      await tester.tap(find.byKey(const Key('play_button')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await pressPlay();
    await pumpFor(const Duration(milliseconds: 1000));
    expect(calls, contains('resume'));
    expect(find.text('Stop'), findsOneWidget);
    expect(staff().playheadUnits, isNotNull);
    expect(staff().playheadUnits, greaterThan(12));

    await pumpFor(const Duration(milliseconds: 1300));
    expect(find.text('Play'), findsOneWidget, reason: 'back to Play without pressing Stop');
    expect(find.text('Stop'), findsNothing);
    expect(staff().playheadUnits, isNull);
    expect(staff().showCursor, isTrue);

    // It can be played again straight away.
    await pressPlay();
    await pumpFor(const Duration(milliseconds: 500));
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play_button')));
    await pumpFor(const Duration(milliseconds: 200));
    expect(find.text('Play'), findsOneWidget);
  });
}
