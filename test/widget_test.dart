import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    final score = RhythmScore.empty(title: 'Widget Test');
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(fileName: 'widget_test_score', initialScore: score),
      ),
    );
  }

  testWidgets('Appending quarter notes fills the measure and disables overflow', (tester) async {
    await pumpEditor(tester);

    expect(find.text('0/48 units filled'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('duration_quarter')));
      await tester.pump();
    }

    expect(find.text('48/48 units filled'), findsOneWidget);

    final quarterButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
    final eighthButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_eighth')));
    final sixteenthButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_sixteenth')));
    final tripletButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_eighth_triplet')));
    expect(quarterButton.onPressed, isNull);
    expect(eighthButton.onPressed, isNull);
    expect(sixteenthButton.onPressed, isNull);
    expect(tripletButton.onPressed, isNull);
  });

  testWidgets('Three eighth-note triplets fill exactly one quarter note', (tester) async {
    await pumpEditor(tester);

    expect(find.widgetWithText(ElevatedButton, 'Triplet'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('duration_eighth_triplet')));
      await tester.pump();
    }
    expect(find.text('12/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backspace')));
    await tester.pump();
    expect(find.text('8/48 units filled'), findsOneWidget);

    // 3 quarters + 2 triplets leaves 4 units: room for one more triplet, but
    // not for an eighth (6).
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('duration_quarter')));
      await tester.pump();
    }
    expect(find.text('44/48 units filled'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byKey(const Key('duration_eighth'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('duration_eighth_triplet')));
    await tester.pump();
    expect(find.text('48/48 units filled'), findsOneWidget);
  });

  testWidgets('On a narrow screen the note buttons scroll sideways instead of overflowing',
      (tester) async {
    // The test font is much wider than the real one, so "narrow" here is
    // wider than a phone: the widest screen the note buttons still don't fit
    // on, without the other rows running out of room too.
    const screenWidth = 480.0;
    tester.view.physicalSize = const Size(screenWidth, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Any RenderFlex overflow would fail the test here.
    await pumpEditor(tester);

    final strip = find.descendant(
      of: find.byKey(const Key('note_entry_strip')),
      matching: find.byType(Scrollable),
    );
    expect(tester.state<ScrollableState>(strip).position.maxScrollExtent, greaterThan(0));

    // The last button in the row starts off-screen; scrolling the strip
    // brings it within reach.
    final backspace = find.byKey(const Key('backspace'));
    expect(tester.getRect(backspace).right, greaterThan(screenWidth));
    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();
    await tester.scrollUntilVisible(backspace, 50, scrollable: strip);
    await tester.pump();
    expect(tester.getRect(backspace).right, lessThanOrEqualTo(screenWidth));
    await tester.tap(backspace);
    await tester.pump();
    expect(find.text('0/48 units filled'), findsOneWidget);
  });

  testWidgets('Backspace removes the last appended event', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('duration_eighth')));
    await tester.pump();
    expect(find.text('6/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backspace')));
    await tester.pump();
    expect(find.text('0/48 units filled'), findsOneWidget);

    final backspaceButton = tester.widget<IconButton>(find.byKey(const Key('backspace')));
    expect(backspaceButton.onPressed, isNull);
  });

  testWidgets('Measure tab strip keeps each measure independent', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();
    expect(find.text('12/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('measure_tab_1')));
    await tester.pump();
    expect(find.text('0/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('measure_tab_0')));
    await tester.pump();
    expect(find.text('12/48 units filled'), findsOneWidget);
  });

  testWidgets('Selecting a type applies it to subsequently appended notes', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('type_rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();

    // A rest quarter still fills 12 units even though it's silent.
    expect(find.text('12/48 units filled'), findsOneWidget);
  });

  testWidgets('Changing the meter updates the button label and measure capacity', (tester) async {
    await pumpEditor(tester);

    expect(find.text('Meter: 4/4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();
    expect(find.text('12/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meter_option_7_4')));
    await tester.pumpAndSettle();

    expect(find.text('Meter: 7/4'), findsOneWidget);
    // The quarter note already entered still fits, so it stays.
    expect(find.text('12/84 units filled'), findsOneWidget);

    // Regression: the duration buttons must stay enabled past 4 quarter
    // notes under a meter wider than 4/4, not disable at the old 4/4 cap.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('duration_quarter')));
      await tester.pump();
    }
    expect(find.text('60/84 units filled'), findsOneWidget);
    final quarterButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
    expect(quarterButton.onPressed, isNotNull);
  });

  testWidgets('A half-note meter (e.g. 3/2) is selectable and sizes the measure correctly',
      (tester) async {
    await pumpEditor(tester);

    // The combined list (16 + divider + 8 entries) can overflow the popup's
    // visible area, so scroll an option into view before tapping it -- same
    // reasoning as practice_screen_test.dart's ensureVisible usage.
    Future<void> selectMeterOption(String key) async {
      await tester.tap(find.byKey(const Key('meter_button')));
      await tester.pumpAndSettle();
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await selectMeterOption('meter_option_3_2');

    expect(find.text('Meter: 3/2'), findsOneWidget);
    // 3 beats * 24 units per half-note beat = 72.
    expect(find.text('0/72 units filled'), findsOneWidget);

    // The 1/2 family's max (8/2) is reachable, independent of the 1/4
    // family's max (16/4) shown in the same popup.
    await tester.tap(find.byKey(const Key('meter_button')));
    await tester.pumpAndSettle();
    final option8of2 = find.byKey(const Key('meter_option_8_2'));
    await tester.ensureVisible(option8of2);
    await tester.pumpAndSettle();
    expect(option8of2, findsOneWidget);
    expect(find.byKey(const Key('meter_option_9_2')), findsNothing);
    // Dismiss the open popup (tap the modal barrier) without selecting.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await selectMeterOption('meter_option_16_4');
    expect(find.text('Meter: 16/4'), findsOneWidget);
  });

  group('Time signatures per measure', () {
    Future<void> selectMeter(WidgetTester tester, String optionKey) async {
      await tester.tap(find.byKey(const Key('meter_button')));
      await tester.pumpAndSettle();
      final option = find.byKey(Key(optionKey));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    Future<void> goToMeasure(WidgetTester tester, int index) async {
      final tab = find.byKey(Key('measure_tab_$index'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pump();
    }

    Future<void> addQuarters(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.tap(find.byKey(const Key('duration_quarter')));
        await tester.pump();
      }
    }

    testWidgets('A meter applies from the measure it is chosen on, not to earlier ones',
        (tester) async {
      await pumpEditor(tester);

      await goToMeasure(tester, 2);
      await selectMeter(tester, 'meter_option_3_4');
      expect(find.text('Meter: 3/4'), findsOneWidget);

      for (final (index, expected) in [(0, '4/4'), (1, '4/4'), (2, '3/4'), (5, '3/4'), (7, '3/4')]) {
        await goToMeasure(tester, index);
        expect(find.text('Meter: $expected'), findsOneWidget, reason: 'measure ${index + 1}');
      }
    });

    testWidgets(
        'Going back to change a meter leaves later measures that already have notes alone',
        (tester) async {
      await pumpEditor(tester);

      // Measures 2 and 4 get notes in 4/4.
      await goToMeasure(tester, 1);
      await addQuarters(tester, 4);
      await goToMeasure(tester, 3);
      await addQuarters(tester, 2);

      // Now measure 1 (and on) changes to 3/4.
      await goToMeasure(tester, 0);
      await selectMeter(tester, 'meter_option_3_4');
      expect(find.textContaining('Measures 2, 4 already have notes'), findsOneWidget);

      for (final (index, meter, filled) in [
        (0, '3/4', '0/36'),
        (1, '4/4', '48/48'), // filled: untouched
        (2, '3/4', '0/36'),
        (3, '4/4', '24/48'), // has notes: untouched, though not full
        (4, '3/4', '0/36'),
        (7, '3/4', '0/36'),
      ]) {
        await goToMeasure(tester, index);
        expect(find.text('Meter: $meter'), findsOneWidget, reason: 'measure ${index + 1}');
        expect(find.text('$filled units filled'), findsOneWidget, reason: 'measure ${index + 1}');
      }
    });

    testWidgets('Notes that no longer fit the new meter are removed from the end, and it says so',
        (tester) async {
      await pumpEditor(tester);
      await addQuarters(tester, 4);

      await selectMeter(tester, 'meter_option_2_4');

      expect(find.text('24/24 units filled'), findsOneWidget);
      expect(find.textContaining('Removed the last 2 entries of measure 1'), findsOneWidget);
    });

    testWidgets('A new measure takes the last measure\'s meter', (tester) async {
      await pumpEditor(tester);
      await goToMeasure(tester, 7);
      await selectMeter(tester, 'meter_option_5_4');

      final add = find.byKey(const Key('measure_tab_add'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.text('Meter: 5/4'), findsOneWidget);
      expect(find.text('0/60 units filled'), findsOneWidget);
    });
  });

  testWidgets('Changing the instrument updates the button label', (tester) async {
    await pumpEditor(tester);

    expect(find.text('Instrument: Snare'), findsOneWidget);

    await tester.tap(find.byKey(const Key('instrument_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instrument_option_kick')));
    await tester.pumpAndSettle();

    expect(find.text('Instrument: Kick'), findsOneWidget);
  });

  testWidgets('The + button appends a new empty measure and jumps to it', (tester) async {
    await pumpEditor(tester);

    // The score starts with 8 measures (indices 0-7); tab 8 doesn't exist yet.
    expect(find.byKey(const Key('measure_tab_7')), findsOneWidget);
    expect(find.byKey(const Key('measure_tab_8')), findsNothing);

    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();
    expect(find.text('12/48 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('measure_tab_add')));
    await tester.pump();

    // Jumped straight to the new (empty) 9th measure.
    expect(find.byKey(const Key('measure_tab_8')), findsOneWidget);
    expect(find.text('0/48 units filled'), findsOneWidget);

    // The earlier measure's content is untouched.
    await tester.tap(find.byKey(const Key('measure_tab_0')));
    await tester.pump();
    expect(find.text('12/48 units filled'), findsOneWidget);
  });
}
