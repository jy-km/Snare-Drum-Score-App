import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/services/midi_score_codec.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

const n = EventType.normal;
const q = RhythmEvent(NoteValue.quarter, n);
const rest = RhythmEvent(NoteValue.quarter, EventType.rest);

RhythmScore scoreOf(List<List<RhythmEvent>> measures) =>
    RhythmScore(title: 'D', tempoBpm: 60, measures: [for (final m in measures) Measure(m)]);

void main() {
  group('In the score', () {
    test('A rest carries no dynamics; changing a note keeps its own', () {
      const marked = RhythmEvent(
        NoteValue.quarter,
        n,
        dynamicMark: DynamicMark.f,
        hairpinStart: Hairpin.crescendo,
        hairpinEnd: true,
      );
      expect(marked.copyWith(type: EventType.rest).hasDynamics, isFalse);
      final longer = marked.copyWith(value: NoteValue.half, ornament: Ornament.flam);
      expect(
        (longer.dynamicMark, longer.hairpinStart, longer.hairpinEnd),
        (DynamicMark.f, Hairpin.crescendo, true),
      );
      expect(marked.copyWith(clearDynamicMark: true).dynamicMark, isNull);
    });

    test('Each note plays at the latest marking at or before it', () {
      final score = scoreOf([
        [q, q.copyWith(dynamicMark: DynamicMark.p), rest, q],
        [q.copyWith(dynamicMark: DynamicMark.ff), q, q, q],
      ]);
      expect(score.dynamicMarkAtNotes, [
        null,
        DynamicMark.p,
        DynamicMark.p,
        DynamicMark.ff,
        DynamicMark.ff,
        DynamicMark.ff,
        DynamicMark.ff,
      ]);
    });

    test('A hairpin runs to its end mark, else into the next marking, else to the last note', () {
      final start = q.copyWith(hairpinStart: Hairpin.crescendo);
      expect(
        scoreOf([
          [start, q, q.copyWith(hairpinEnd: true), q],
        ]).hairpinSpans,
        [const HairpinSpan(Hairpin.crescendo, 0, 2)],
      );
      expect(
        scoreOf([
          [start, q, q, q.copyWith(dynamicMark: DynamicMark.f)],
          [q, q, q, q],
        ]).hairpinSpans,
        [const HairpinSpan(Hairpin.crescendo, 0, 3)],
      );
      expect(
        scoreOf([
          [start, q, q, q],
          [q, q, q, q],
        ]).hairpinSpans,
        [const HairpinSpan(Hairpin.crescendo, 0, 7)],
      );
      // A new one starting first ends it at the note before.
      expect(
        scoreOf([
          [start, q, q.copyWith(hairpinStart: Hairpin.decrescendo), q],
        ]).hairpinSpans,
        [const HairpinSpan(Hairpin.crescendo, 0, 1), const HairpinSpan(Hairpin.decrescendo, 2, 3)],
      );
    });

    test('A hairpin over a barline is drawn in two parts, opening across both', () {
      final score = scoreOf([
        [q, q, q.copyWith(hairpinStart: Hairpin.crescendo), q],
        [q, q.copyWith(hairpinEnd: true), q, q],
      ]);
      // From 24 units into measure 1 to the middle of the second note of
      // measure 2 (12 + 6 units in): 42 units, split 24 + 18.
      final first = score.hairpinSegmentsIn(0).single;
      final second = score.hairpinSegmentsIn(1).single;
      expect((first.startUnits, first.endUnits), (24.0, 48.0));
      expect((second.startUnits, second.endUnits), (0.0, 18.0));
      expect(first.startFraction, 0);
      expect(first.endFraction, closeTo(24 / 42, 1e-9));
      expect(second.startFraction, closeTo(24 / 42, 1e-9));
      expect(second.endFraction, 1);
    });
  });

  test('Dynamics are saved and read back; text from other programs is ignored', () {
    final score = scoreOf([
      [
        q.copyWith(dynamicMark: DynamicMark.pp, hairpinStart: Hairpin.crescendo),
        rest,
        q.copyWith(type: EventType.accent),
        q.copyWith(dynamicMark: DynamicMark.ff, hairpinEnd: true),
      ],
      [
        q.copyWith(dynamicMark: DynamicMark.mf, hairpinStart: Hairpin.decrescendo),
        q,
        q,
        q.copyWith(dynamicMark: DynamicMark.mp),
      ],
    ]);
    expect(MidiScoreCodec.decode(MidiScoreCodec.encode(score)), score);

    final plain = scoreOf([
      [q, q, q, q],
    ]);
    expect(MidiScoreCodec.decode(MidiScoreCodec.encode(plain)), plain, reason: 'unchanged');
  });

  group('In the editor', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ScoreEditorScreen(
            fileName: 'dynamics_test',
            initialScore: scoreOf([
              [q, q, q, q],
              [q, q, q, q],
            ]),
          ),
        ),
      );
    }

    Measure shown(WidgetTester tester) =>
        tester.widget<StaffNotationView>(find.byKey(const Key('editor_staff'))).measure;

    Future<void> tapButton(WidgetTester tester, String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Taps the [index]th quarter note of the measure shown.
    Future<void> tapNote(WidgetTester tester, int index) async {
      final staff = find.byKey(const Key('editor_staff'));
      await tester.ensureVisible(staff);
      await tester.pumpAndSettle();
      final view = tester.widget<StaffNotationView>(staff);
      final rect = tester.getRect(staff);
      final x = StaffNotationView.xForUnits(
        view.measure,
        showTimeSignature: view.showTimeSignature,
        width: rect.width,
        units: index * 12.0,
      );
      await tester.tapAt(Offset(rect.left + x + 2, rect.center.dy));
      await tester.pump();
    }

    bool enabled(WidgetTester tester, String key) =>
        tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed != null;

    testWidgets('Dynamics need a picked note', (tester) async {
      await pumpEditor(tester);
      expect(enabled(tester, 'dynamic_f'), isFalse);
      expect(enabled(tester, 'hairpin_crescendo'), isFalse);
      await tapNote(tester, 1);
      expect(enabled(tester, 'dynamic_f'), isTrue);
    });

    testWidgets('A marking is written at the picked note, and taken off again', (tester) async {
      await pumpEditor(tester);
      await tapNote(tester, 1);
      await tapButton(tester, 'dynamic_f');
      expect(shown(tester).events[1].dynamicMark, DynamicMark.f);

      await tapButton(tester, 'dynamic_p');
      expect(shown(tester).events[1].dynamicMark, DynamicMark.p, reason: 'one at a time');

      await tapButton(tester, 'dynamic_p');
      expect(shown(tester).events[1].dynamicMark, isNull);
    });

    testWidgets('Changing a marked note\'s length or type keeps its marking', (tester) async {
      await pumpEditor(tester);
      await tapNote(tester, 0);
      await tapButton(tester, 'dynamic_mp');
      await tapButton(tester, 'duration_eighth');
      await tapButton(tester, 'type_accent');
      final event = shown(tester).events[0];
      expect(
        (event.value, event.type, event.dynamicMark),
        (NoteValue.eighth, EventType.accent, DynamicMark.mp),
      );
    });

    testWidgets('A crescendo goes from the picked note to the next note tapped -- in another '
        'measure too', (tester) async {
      await pumpEditor(tester);
      await tapNote(tester, 2);
      await tapButton(tester, 'hairpin_crescendo');
      expect(shown(tester).events[2].hairpinStart, Hairpin.crescendo);
      expect(find.byKey(const Key('hairpin_end_hint')), findsOneWidget);

      await tapButton(tester, 'measure_tab_1');
      await tapNote(tester, 1);

      expect(find.byKey(const Key('hairpin_end_hint')), findsNothing);
      expect(shown(tester).events[1].hairpinEnd, isTrue);
      final segments = tester
          .widget<StaffNotationView>(find.byKey(const Key('editor_staff')))
          .hairpins;
      expect(segments.single.kind, Hairpin.crescendo, reason: 'drawn into measure 2');
    });

    testWidgets('Tapping a note before where it starts is refused', (tester) async {
      await pumpEditor(tester);
      await tapNote(tester, 2);
      await tapButton(tester, 'hairpin_decrescendo');
      await tapNote(tester, 0);
      expect(find.text('Pick a note at or after where it starts.'), findsOneWidget);
      expect(shown(tester).events[0].hairpinEnd, isFalse);
      expect(find.byKey(const Key('hairpin_end_hint')), findsOneWidget, reason: 'still waiting');
    });

    testWidgets('Tapping the button again leaves it running; again on the note takes it off with '
        'its end', (tester) async {
      await pumpEditor(tester);
      await tapNote(tester, 0);
      await tapButton(tester, 'hairpin_crescendo');
      await tapButton(tester, 'hairpin_crescendo');
      expect(find.byKey(const Key('hairpin_end_hint')), findsNothing);
      expect(shown(tester).events[0].hairpinStart, Hairpin.crescendo, reason: 'still there');

      // Give it an end, then take it off from its start.
      await tapButton(tester, 'hairpin_crescendo'); // off
      await tapNote(tester, 0); // let go
      await tapNote(tester, 0);
      await tapButton(tester, 'hairpin_crescendo');
      await tapNote(tester, 3);
      expect(shown(tester).events[3].hairpinEnd, isTrue);
      await tapNote(tester, 0);
      await tapButton(tester, 'hairpin_crescendo');
      expect(shown(tester).events[0].hairpinStart, isNull);
      expect(shown(tester).events[3].hairpinEnd, isFalse, reason: 'its end goes with it');
    });
  });
}
