import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';

void main() {
  testWidgets('Tapping a grid cell cycles rest -> normal -> accent -> rest', (tester) async {
    final score = RhythmScore.empty(title: 'Widget Test');
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(fileName: 'widget_test_score', initialScore: score),
      ),
    );

    final cell = find.byKey(const Key('beat_cell_0'));
    expect(cell, findsOneWidget);
    expect(find.text('>'), findsNothing);

    await tester.tap(cell); // rest -> normal
    await tester.pump();
    expect(find.text('>'), findsNothing);

    await tester.tap(cell); // normal -> accent
    await tester.pump();
    expect(find.text('>'), findsOneWidget);

    await tester.tap(cell); // accent -> rest
    await tester.pump();
    expect(find.text('>'), findsNothing);
  });

  testWidgets('Measure tab strip switches the visible measure', (tester) async {
    final score = RhythmScore.empty(title: 'Widget Test');
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreEditorScreen(fileName: 'widget_test_score', initialScore: score),
      ),
    );

    // Mark measure 1's first cell, then switch to measure 2 and confirm its
    // grid starts empty (measures are independent).
    await tester.tap(find.byKey(const Key('beat_cell_0')));
    await tester.pump();
    expect(find.text('>'), findsNothing);

    await tester.tap(find.byKey(const Key('measure_tab_1')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('beat_cell_0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('beat_cell_0')));
    await tester.pump();
    expect(find.text('>'), findsOneWidget);
  });
}
