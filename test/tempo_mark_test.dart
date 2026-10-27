import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/widgets/tempo_mark.dart';

void main() {
  test('Each beat note has its own metronome-mark note', () {
    final glyphs = {for (final beat in TempoBeat.values) TempoMark.glyph(beat)};
    expect(glyphs, hasLength(TempoBeat.values.length));
    expect(TempoMark.glyph(TempoBeat.quarter), '\uECA5');
  });

  testWidgets('Reads as the note then "= 130", and says so to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TempoMark(beat: TempoBeat.eighth, bpm: 130)),
      ),
    );

    expect(
      find.text('${TempoMark.glyph(TempoBeat.eighth)} = 130', findRichText: true),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('130 beats a minute, one beat an eighth note'), findsOneWidget);
    semantics.dispose();
  });
}
