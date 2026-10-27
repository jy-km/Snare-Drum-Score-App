import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/services/score_storage.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, {RhythmScore? score}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(
          fileName: 'gestures_test',
          initialScore: score ?? RhythmScore.empty(title: 'Gestures'),
        ),
      ),
    );
  }

  Future<void> tapButton(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Measure staffMeasure(WidgetTester tester) =>
      tester.widget<StaffNotationView>(find.byKey(const Key('editor_staff'))).measure;

  String tempoText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('tempo_field'))).controller!.text;

  group('Long press on backspace', () {
    testWidgets('clears the whole measure and keeps its time signature', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'meter_button');
      await tapButton(tester, 'meter_option_3_4');
      for (var i = 0; i < 3; i++) {
        await tapButton(tester, 'duration_quarter');
      }
      expect(find.text('3 of 3 beats filled'), findsOneWidget);

      await tester.longPress(find.byKey(const Key('backspace')));
      await tester.pump();

      expect(staffMeasure(tester).events, isEmpty);
      expect(find.text('0 of 3 beats filled'), findsOneWidget);
      expect(find.text('Measure 1 cleared'), findsOneWidget);
    });

    testWidgets('leaves the other measures alone', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'duration_quarter');
      await tapButton(tester, 'measure_tab_1');
      await tapButton(tester, 'duration_eighth');
      await tapButton(tester, 'duration_eighth');

      await tester.longPress(find.byKey(const Key('backspace')));
      await tester.pump();
      expect(staffMeasure(tester).events, isEmpty);

      await tapButton(tester, 'measure_tab_0');
      expect(staffMeasure(tester).events.map((e) => e.value), [NoteValue.quarter]);
    });

    testWidgets('a short tap still removes only the last note', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'duration_quarter');
      await tapButton(tester, 'duration_quarter');

      await tapButton(tester, 'backspace');

      expect(staffMeasure(tester).events, hasLength(1));
    });

    testWidgets('Undo brings the notes back', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'duration_quarter');
      await tapButton(tester, 'duration_eighth');

      await tester.longPress(find.byKey(const Key('backspace')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(staffMeasure(tester).events.map((e) => e.value), [
        NoteValue.quarter,
        NoteValue.eighth,
      ]);
    });

    testWidgets('Undo does nothing once the measure has been written in again', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'duration_quarter');
      await tapButton(tester, 'duration_quarter');

      await tester.longPress(find.byKey(const Key('backspace')));
      await tester.pumpAndSettle();
      await tapButton(tester, 'duration_sixteenth');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(staffMeasure(tester).events.map((e) => e.value), [NoteValue.sixteenth]);
    });

    testWidgets('does nothing on an empty measure', (tester) async {
      await pumpEditor(tester);

      await tester.longPress(find.byKey(const Key('backspace')), warnIfMissed: false);
      await tester.pump();

      expect(find.textContaining('cleared'), findsNothing);
    });
  });

  group('Half notes and half rests', () {
    testWidgets('a half note takes two beats of a 4/4 measure', (tester) async {
      await pumpEditor(tester);

      await tapButton(tester, 'duration_half');
      expect(find.text('2 of 4 beats filled'), findsOneWidget);
      await tapButton(tester, 'type_rest');
      await tapButton(tester, 'duration_half');

      expect(find.text('4 of 4 beats filled'), findsOneWidget);
      expect(staffMeasure(tester).events, const [
        RhythmEvent(NoteValue.half, EventType.normal),
        RhythmEvent(NoteValue.half, EventType.rest),
      ]);
    });

    testWidgets('the button is disabled when less than a half note is left', (tester) async {
      await pumpEditor(tester);
      for (var i = 0; i < 3; i++) {
        await tapButton(tester, 'duration_quarter');
      }

      final half = tester.widget<ElevatedButton>(find.byKey(const Key('duration_half')));
      final quarter = tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
      expect(half.onPressed, isNull);
      expect(quarter.onPressed, isNotNull);
    });

    testWidgets('a half-note beat is one half note in a 3/2 measure', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'meter_button');
      await tapButton(tester, 'meter_option_3_2');

      await tapButton(tester, 'duration_half');

      expect(find.text('1 of 3 beats filled'), findsOneWidget);
    });
  });

  group('Long press on the tempo, then swipe', () {
    /// Holds the tempo number, then moves the finger by [dy] (negative = up).
    Future<TestGesture> holdAndSwipe(WidgetTester tester, double dy) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('tempo_field'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump();
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump();
      return gesture;
    }

    testWidgets('up raises the tempo', (tester) async {
      await pumpEditor(tester);
      expect(tempoText(tester), '100');

      final gesture = await holdAndSwipe(tester, -80);
      expect(tempoText(tester), '120');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tempoText(tester), '120');
    });

    testWidgets('down lowers the tempo', (tester) async {
      await pumpEditor(tester);

      final gesture = await holdAndSwipe(tester, 60);
      expect(tempoText(tester), '85');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('stops at the slowest and fastest tempo', (tester) async {
      await pumpEditor(tester);

      var gesture = await holdAndSwipe(tester, 2000);
      expect(tempoText(tester), '20');
      await gesture.up();
      await tester.pumpAndSettle();

      gesture = await holdAndSwipe(tester, -4000);
      expect(tempoText(tester), '300');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the page does not scroll and no text is selected meanwhile', (tester) async {
      await pumpEditor(tester);
      final before = tester.getTopLeft(find.byKey(const Key('tempo_field')));

      final gesture = await holdAndSwipe(tester, -80);
      expect(tester.getTopLeft(find.byKey(const Key('tempo_field'))), before);
      final controller = tester.widget<TextField>(find.byKey(const Key('tempo_field'))).controller!;
      expect(controller.selection.isCollapsed, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a swipe without holding first leaves the tempo alone', (tester) async {
      await pumpEditor(tester);

      await tester.drag(find.byKey(const Key('tempo_field')), const Offset(0, -80));
      await tester.pumpAndSettle();

      expect(tempoText(tester), '100');
    });

    testWidgets('the tempo can still be typed', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('tempo_field')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byKey(const Key('tempo_field')), '72');

      expect(tempoText(tester), '72');
    });
  });

  group('Tempo beat', () {
    testWidgets('starts at the quarter note; choosing another keeps the BPM number', (
      tester,
    ) async {
      await pumpEditor(tester, score: RhythmScore.empty(title: 'Beat', tempoBpm: 150));
      expect(find.byKey(const Key('tempo_beat_quarter')), findsOneWidget);

      await tapButton(tester, 'tempo_beat_button');
      await tapButton(tester, 'tempo_beat_option_half');
      expect(find.byKey(const Key('tempo_beat_half')), findsOneWidget);
      expect(tempoText(tester), '150');

      await tapButton(tester, 'tempo_beat_button');
      await tapButton(tester, 'tempo_beat_option_eighth');
      expect(find.byKey(const Key('tempo_beat_eighth')), findsOneWidget);

      await tapButton(tester, 'tempo_beat_button');
      await tapButton(tester, 'tempo_beat_option_dottedQuarter');
      expect(find.byKey(const Key('tempo_beat_dottedQuarter')), findsOneWidget);
      expect(tempoText(tester), '150');
    });

    testWidgets('is saved with the score', (tester) async {
      final storage = _MemoryScoreStorage();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ScoreEditorScreen(
            fileName: 'beat_test',
            initialScore: RhythmScore.empty(title: 'Beat', tempoBpm: 150),
            storage: storage,
          ),
        ),
      );
      await tapButton(tester, 'tempo_beat_button');
      await tapButton(tester, 'tempo_beat_option_half');
      await tapButton(tester, 'save_button');
      expect(storage.saved['beat_test']?.tempoBeat, TempoBeat.half);
      expect(storage.saved['beat_test']?.tempoBpm, 150);
    });
  });
}

class _MemoryScoreStorage extends ScoreStorage {
  final saved = <String, RhythmScore>{};

  @override
  Future<void> save(String fileName, RhythmScore score) async => saved[fileName] = score;
}
