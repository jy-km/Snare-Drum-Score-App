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

    expect(find.text('0/16 units filled'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('duration_quarter')));
      await tester.pump();
    }

    expect(find.text('16/16 units filled'), findsOneWidget);

    final quarterButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_quarter')));
    final eighthButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_eighth')));
    final sixteenthButton =
        tester.widget<ElevatedButton>(find.byKey(const Key('duration_sixteenth')));
    expect(quarterButton.onPressed, isNull);
    expect(eighthButton.onPressed, isNull);
    expect(sixteenthButton.onPressed, isNull);
  });

  testWidgets('Backspace removes the last appended event', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('duration_eighth')));
    await tester.pump();
    expect(find.text('2/16 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backspace')));
    await tester.pump();
    expect(find.text('0/16 units filled'), findsOneWidget);

    final backspaceButton = tester.widget<IconButton>(find.byKey(const Key('backspace')));
    expect(backspaceButton.onPressed, isNull);
  });

  testWidgets('Measure tab strip keeps each measure independent', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();
    expect(find.text('4/16 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('measure_tab_1')));
    await tester.pump();
    expect(find.text('0/16 units filled'), findsOneWidget);

    await tester.tap(find.byKey(const Key('measure_tab_0')));
    await tester.pump();
    expect(find.text('4/16 units filled'), findsOneWidget);
  });

  testWidgets('Selecting a type applies it to subsequently appended notes', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const Key('type_rest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('duration_quarter')));
    await tester.pump();

    // A rest quarter still fills 4 units even though it's silent.
    expect(find.text('4/16 units filled'), findsOneWidget);
  });
}
