import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/widgets/waveform_view.dart';

import 'dynamics_check_test.dart' show playedAt, quarters, marked, plain;

void main() {
  // Eight quarter notes at 60 BPM after a 4s count-in (due at 4-11s), the
  // third not played. The wave runs from 3.75s to 12.5s.
  final review = playedAt(
    quarters([
      marked(DynamicMark.p),
      plain,
      plain,
      plain,
      marked(DynamicMark.f),
      plain,
      plain,
      plain,
    ]),
    [0.25, 0.3, null, 0.3, 1, 0.9, 1, 0.8],
  );
  const from = 3.75;
  const to = 12.5;

  Future<void> pumpWave(WidgetTester tester, {double? playhead}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaveformView(review: review, playheadSeconds: playhead),
        ),
      ),
    );
  }

  String caption(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('waveform_caption'))).data!;

  ScrollPosition scroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('waveform_scroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  /// Taps the wave at [seconds], at 1x.
  Future<void> tapAt(WidgetTester tester, double seconds) async {
    final rect = tester.getRect(find.byKey(const Key('waveform_scroll')));
    await tester.tapAt(
      Offset(rect.left + (seconds - from) / (to - from) * rect.width, rect.center.dy),
    );
    await tester.pump();
  }

  testWidgets('Tapping near a note says its timing and how loud it was', (tester) async {
    await pumpWave(tester);
    expect(caption(tester), 'Tap near a note to see its timing and how loud it was.');

    await tapAt(tester, 8.0);
    expect(
      caption(tester),
      matches(RegExp(r'^Measure 2, note 1: Perfect, 0 ms \(on time\), -\d+ dB$')),
    );

    await tapAt(tester, 6.0);
    expect(caption(tester), 'Measure 1, note 3: not played');
  });

  testWidgets('A louder hit reads louder', (tester) async {
    await pumpWave(tester);
    int db() => int.parse(RegExp(r'(-\d+) dB').firstMatch(caption(tester))!.group(1)!);
    await tapAt(tester, 4.0); // p
    final soft = db();
    await tapAt(tester, 8.0); // f
    expect(db(), greaterThan(soft + 6));
  });

  testWidgets('Zooms in and out, in steps, from fitting the screen to 16 times', (tester) async {
    await pumpWave(tester);
    expect(scroll(tester).maxScrollExtent, 0, reason: 'fits the screen');
    expect(tester.widget<IconButton>(find.byKey(const Key('waveform_zoom_out'))).onPressed, isNull);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('waveform_zoom_in')));
      await tester.pump();
    }
    expect(find.text('16×'), findsOneWidget);
    expect(scroll(tester).maxScrollExtent, greaterThan(scroll(tester).viewportDimension * 14));
    expect(tester.widget<IconButton>(find.byKey(const Key('waveform_zoom_in'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('waveform_zoom_out')));
    await tester.pump();
    expect(find.text('8×'), findsOneWidget);
  });

  testWidgets('Zoomed in, it keeps the replay\'s playhead in view', (tester) async {
    await pumpWave(tester, playhead: 4.0);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('waveform_zoom_in')));
      await tester.pump();
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaveformView(review: review, playheadSeconds: 11.0)),
      ),
    );
    await tester.pump();
    final position = scroll(tester);
    final playheadX = (11.0 - from) / (to - from) * position.viewportDimension * 4;
    expect(playheadX, greaterThanOrEqualTo(position.pixels));
    expect(playheadX, lessThanOrEqualTo(position.pixels + position.viewportDimension));
  });

  testWidgets('Is on the review screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReviewScreen(review: review)));
    expect(find.byKey(const Key('review_waveform')), findsOneWidget);
  });
}
