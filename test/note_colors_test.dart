import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/screens/settings_screen.dart';
import 'package:snare_drum_score_app/services/app_settings.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/run_review.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';
import 'package:snare_drum_score_app/widgets/judgement_style.dart';
import 'package:snare_drum_score_app/widgets/settings_scope.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

/// Remembers settings only for as long as the test runs.
class InMemorySettingsStore implements SettingsStore {
  Map<String, Object?> values;

  InMemorySettingsStore([this.values = const {}]);

  @override
  Future<Map<String, Object?>> load() async => values;

  @override
  Future<void> save(Map<String, Object?> values) async => this.values = values;
}

void main() {
  // 60 BPM, count-in then one 4/4 measure: quarter note, quarter rest,
  // quarter note, quarter note -- notes due at 4s, 6s and 7s.
  final score = RhythmScore(
    title: 'Colours',
    tempoBpm: 60,
    measures: [
      Measure(const [
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.rest),
        RhythmEvent(NoteValue.quarter, EventType.normal),
        RhythmEvent(NoteValue.quarter, EventType.accent),
      ]),
      Measure(const [RhythmEvent(NoteValue.quarter, EventType.normal)]),
    ],
  );
  final layout = TimelineLayout(score);
  const judgements = [
    JudgedHit(Judgement.perfect, noteIndex: 0, offsetSeconds: 0.01, hitTimeSeconds: 4.01),
    JudgedHit(Judgement.fail, hitTimeSeconds: 5.5), // in the rest
    JudgedHit(Judgement.good, noteIndex: 1, offsetSeconds: 0.1, hitTimeSeconds: 6.1),
    JudgedHit(Judgement.miss, noteIndex: 2),
    JudgedHit(Judgement.fail, hitTimeSeconds: 9.5), // measure 2's unfilled end
  ];

  test('Each judged note gets its judgement\'s colour; a rest played in gets the Fail colour',
      () {
    final colors = judgementEventColors(judgements, layout: layout, secondsPerUnit: 1 / 12);

    expect(colors[1], {
      0: judgementColor(Judgement.perfect),
      1: judgementColor(Judgement.fail),
      2: judgementColor(Judgement.good),
      3: judgementColor(Judgement.miss),
    });
    // Measure 2's only note wasn't judged, and its fail landed where there
    // is no rest to colour.
    expect(colors[2], isNull);
  });

  test('Perfect is yellow and Miss red, with Fail apart from Miss', () {
    final perfect = HSVColor.fromColor(judgementColor(Judgement.perfect));
    expect(perfect.hue, inInclusiveRange(40, 60), reason: 'yellow');
    final miss = HSVColor.fromColor(judgementColor(Judgement.miss));
    expect(miss.hue < 10 || miss.hue > 350, isTrue, reason: 'red');
    expect(judgementColor(Judgement.fail), isNot(judgementColor(Judgement.miss)));
  });

  group('Settings', () {
    testWidgets('The switch turns the mode on and off, and is remembered', (tester) async {
      final store = InMemorySettingsStore();
      final settings = AppSettings(store: store);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SettingsScope(settings: settings, child: child!),
          home: const SettingsScreen(),
        ),
      );

      final toggle = find.byKey(const Key('setting_color_notes'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse, reason: 'off by default');

      await tester.tap(toggle);
      await tester.pump();
      expect(settings.colorNotesByJudgement, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(store.values['colorNotesByJudgement'], isTrue);

      await tester.tap(toggle);
      await tester.pump();
      expect(store.values['colorNotesByJudgement'], isFalse);
    });

    test('Saved settings are loaded back', () async {
      final settings = AppSettings(store: InMemorySettingsStore({'colorNotesByJudgement': true}));
      expect(settings.colorNotesByJudgement, isFalse, reason: 'defaults until loaded');

      await settings.load();

      expect(settings.colorNotesByJudgement, isTrue);
    });
  });

  group('Review', () {
    RunReview review() => RunReview(
          layout: layout,
          secondsPerUnit: 1 / 12,
          noteTimes: [4.0, 6.0, 7.0, 8.0],
          judgements: judgements,
          counts: const {},
          audio: Int16List(44100),
          sampleRate: 44100,
          timingEstimated: false,
        );

    Map<int, Color> colorsOfMeasure1(WidgetTester tester) =>
        tester.widget<StaffNotationView>(find.byKey(const Key('review_measure_1'))).eventColors;

    Future<void> pumpReview(WidgetTester tester, AppSettings settings) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SettingsScope(settings: settings, child: child!),
          home: ReviewScreen(review: review()),
        ),
      );
    }

    testWidgets('With the mode on, notes are drawn in their judgement\'s colour', (tester) async {
      final settings = AppSettings()..colorNotesByJudgement = true;
      await pumpReview(tester, settings);

      expect(colorsOfMeasure1(tester)[0], judgementColor(Judgement.perfect));
      expect(colorsOfMeasure1(tester)[3], judgementColor(Judgement.miss));
    });

    testWidgets('With the mode off, notes stay black -- and it follows the setting live',
        (tester) async {
      final settings = AppSettings();
      await pumpReview(tester, settings);
      expect(colorsOfMeasure1(tester), isEmpty);

      settings.colorNotesByJudgement = true;
      await tester.pump();
      expect(colorsOfMeasure1(tester), isNotEmpty);
    });
  });
}
