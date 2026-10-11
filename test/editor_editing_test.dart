import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, {RhythmScore? score}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(
          fileName: 'editing_test',
          initialScore: score ?? RhythmScore.empty(title: 'Editing'),
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

  int? picked(WidgetTester tester) =>
      tester.widget<StaffNotationView>(find.byKey(const Key('editor_staff'))).selectedEventIndex;

  /// Taps the staff at position [units] within the measure shown.
  Future<void> tapStaffAt(WidgetTester tester, double units) async {
    final staff = find.byKey(const Key('editor_staff'));
    final view = tester.widget<StaffNotationView>(staff);
    final rect = tester.getRect(staff);
    final x = StaffNotationView.xForUnits(
      view.measure,
      showTimeSignature: view.showTimeSignature,
      width: rect.width,
      units: units,
    );
    await tester.tapAt(Offset(rect.left + x + 2, rect.center.dy));
    await tester.pump();
  }

  Future<void> enterQuarters(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tapButton(tester, 'duration_quarter');
    }
  }

  group('Editing inside a measure', () {
    testWidgets('Tapping a note picks it; tapping it again lets go', (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 4);

      await tapStaffAt(tester, 26); // inside the third quarter note
      expect(picked(tester), 2);
      expect(find.textContaining('Note 3 picked'), findsOneWidget);

      await tapStaffAt(tester, 26);
      expect(picked(tester), isNull);
    });

    testWidgets('A length button changes the picked note, and later notes move along',
        (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 3);

      await tapStaffAt(tester, 14); // the second quarter
      await tapButton(tester, 'duration_eighth');

      expect(staffMeasure(tester).events.map((e) => e.value), [
        NoteValue.quarter,
        NoteValue.eighth,
        NoteValue.quarter,
      ]);
      expect(find.text('2½ of 4 beats filled'), findsOneWidget);
      expect(picked(tester), 1, reason: 'stays picked for further changes');
    });

    testWidgets('A length that would overflow the measure is disabled for the picked note',
        (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 3);
      await tapButton(tester, 'duration_eighth');
      await tapButton(tester, 'duration_eighth'); // measure now full

      await tapStaffAt(tester, 38); // the first eighth
      expect(picked(tester), 3);
      final quarter = tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
      final sixteenth =
          tester.widget<ElevatedButton>(find.byKey(const Key('duration_sixteenth')));
      expect(quarter.onPressed, isNull, reason: 'a quarter instead of the eighth would overflow');
      expect(sixteenth.onPressed, isNotNull, reason: 'shorter always fits');
    });

    testWidgets('A type button changes the picked note\'s type', (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 2);

      await tapStaffAt(tester, 2);
      await tapButton(tester, 'type_accent');

      expect(staffMeasure(tester).events.map((e) => e.type), [EventType.accent, EventType.normal]);
    });

    testWidgets('Picking a note shows its type on the type buttons', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'type_rest');
      await enterQuarters(tester, 1);
      await tapButton(tester, 'type_normal');
      await enterQuarters(tester, 1);

      await tapStaffAt(tester, 2); // the rest
      final restButton = tester.widget<OutlinedButton>(find.byKey(const Key('type_rest')));
      expect(restButton.style?.backgroundColor?.resolve({}), isNotNull, reason: 'highlighted');
    });

    testWidgets('Backspace removes the picked note and closes the gap', (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'duration_quarter');
      await tapButton(tester, 'duration_eighth');
      await tapButton(tester, 'duration_quarter');

      await tapStaffAt(tester, 13); // the eighth
      await tapButton(tester, 'backspace');

      expect(staffMeasure(tester).events.map((e) => e.value), [NoteValue.quarter, NoteValue.quarter]);
      expect(picked(tester), isNull);
    });

    testWidgets('Tapping past the last note lets go of the pick', (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 1);

      await tapStaffAt(tester, 2);
      expect(picked(tester), 0);
      await tapStaffAt(tester, 40); // empty end of the measure
      expect(picked(tester), isNull);
    });

    testWidgets('Changing measure lets go of the pick', (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 1);
      await tapStaffAt(tester, 2);

      await tapButton(tester, 'measure_tab_1');
      expect(picked(tester), isNull);
    });
  });

  group('Deleting measures', () {
    testWidgets('An empty measure is deleted straight away; later measures move up',
        (tester) async {
      await pumpEditor(tester);
      await tapButton(tester, 'measure_tab_2');
      await enterQuarters(tester, 2); // measure 3 has notes
      await tapButton(tester, 'measure_tab_1');

      await tapButton(tester, 'measure_tab_delete');

      expect(find.byKey(const Key('measure_tab_7')), findsNothing, reason: '7 measures left');
      expect(find.text('2 of 4 beats filled'), findsOneWidget,
          reason: 'the old measure 3 is now measure 2, and is the one shown');
    });

    testWidgets('A measure with notes asks first', (tester) async {
      await pumpEditor(tester);
      await enterQuarters(tester, 2);

      await tapButton(tester, 'measure_tab_delete');
      expect(find.text('Delete measure 1?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 4 beats filled'), findsOneWidget);
      expect(find.byKey(const Key('measure_tab_7')), findsOneWidget);

      await tapButton(tester, 'measure_tab_delete');
      await tester.tap(find.byKey(const Key('delete_measure_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('0 of 4 beats filled'), findsOneWidget);
      expect(find.byKey(const Key('measure_tab_7')), findsNothing);
    });

    testWidgets('The last measure left can\'t be deleted', (tester) async {
      await pumpEditor(tester, score: RhythmScore.empty(title: 'One', measuresCount: 1));

      final delete = find.descendant(
        of: find.byKey(const Key('measure_tab_delete')),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(delete).onPressed, isNull);
    });
  });

  testWidgets('Eighth-note meters (x/8) can be chosen and count in eighths', (tester) async {
    await pumpEditor(tester);

    await tapButton(tester, 'meter_button');
    await tapButton(tester, 'meter_option_7_8');

    expect(find.text('Meter: 7/8'), findsOneWidget);
    expect(find.text('0 of 7 beats filled'), findsOneWidget);
    await enterQuarters(tester, 3);
    expect(find.text('6 of 7 beats filled'), findsOneWidget);
    final quarter = tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
    expect(quarter.onPressed, isNull, reason: 'one eighth left');
  });
}
