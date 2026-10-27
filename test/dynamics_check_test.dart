import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/services/dynamics_check.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/services/run_review.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';

import 'support/synth_audio.dart';

const n = EventType.normal;

/// [events] quarter notes, four to a measure, at 60 BPM: after a 4s
/// count-in, one note a second.
RhythmScore quarters(List<RhythmEvent> events) => RhythmScore(
  title: 'Dynamics',
  tempoBpm: 60,
  measures: [
    for (var start = 0; start < events.length; start += 4)
      Measure(events.sublist(start, start + 4)),
  ],
);

/// A run of [score] with every note hit on time, each [gains] times as loud
/// as usual (null: not played -- a miss).
RunReview playedAt(RhythmScore score, List<double?> gains) {
  final noteTimes = [for (final unit in score.noteStartUnits) 4.0 + unit / 12];
  final played = [
    for (var i = 0; i < noteTimes.length; i++)
      if (gains[i] != null) i,
  ];
  return RunReview(
    layout: TimelineLayout(score),
    secondsPerUnit: 1 / 12,
    noteTimes: noteTimes,
    judgements: [
      for (var i = 0; i < noteTimes.length; i++)
        gains[i] == null
            ? JudgedHit(Judgement.miss, noteIndex: i)
            : JudgedHit(
                Judgement.perfect,
                noteIndex: i,
                offsetSeconds: 0,
                hitTimeSeconds: noteTimes[i],
              ),
    ],
    counts: {for (final judgement in Judgement.values) judgement: 0},
    audio: synthRecording(
      seconds: noteTimes.last + 1,
      hitTimes: [for (final i in played) noteTimes[i]],
      gains: [for (final i in played) gains[i]!],
    ),
    sampleRate: synthSampleRate,
    timingEstimated: false,
  );
}

RhythmEvent marked(DynamicMark mark, {EventType type = n}) =>
    RhythmEvent(NoteValue.quarter, type, dynamicMark: mark);
const plain = RhythmEvent(NoteValue.quarter, n);

void main() {
  test('A hit twice as loud measures about 6 dB louder', () {
    final audio = synthRecording(seconds: 3, hitTimes: [1, 2], gains: [0.5, 1]);
    final soft = DynamicsCheck.hitLoudnessDb(audio, synthSampleRate, 1)!;
    final loud = DynamicsCheck.hitLoudnessDb(audio, synthSampleRate, 2)!;
    expect(loud - soft, closeTo(6, 1)); // each burst is its own random noise
    expect(loud, lessThan(0));
  });

  group('Changes of marking', () {
    final pThenF = quarters([
      marked(DynamicMark.p),
      plain,
      plain,
      plain,
      marked(DynamicMark.f),
      plain,
      plain,
      plain,
    ]);

    test('p then f, played softer then louder: as marked, by how much', () {
      final check = DynamicsCheck.of(playedAt(pThenF, [0.25, 0.25, 0.25, 0.25, 1, 1, 1, 1]));
      expect(check.sections.map((s) => s.mark), [DynamicMark.p, DynamicMark.f]);
      final change = check.changes.single;
      expect(change.louder, isTrue);
      expect(change.differenceDb, closeTo(12, 1));
      expect(change.met, isTrue);
      expect((check.met, check.judged), (1, 1));
    });

    test('p then f played all at one level is not as marked', () {
      final check = DynamicsCheck.of(playedAt(pThenF, List.filled(8, 0.5)));
      expect(check.changes.single.differenceDb!.abs(), lessThan(DynamicsCheck.minChangeDb));
      expect(check.changes.single.met, isFalse);
    });

    test('f then p asks for softer', () {
      final fThenP = quarters([
        marked(DynamicMark.f),
        plain,
        plain,
        plain,
        marked(DynamicMark.p),
        plain,
        plain,
        plain,
      ]);
      expect(
        DynamicsCheck.of(playedAt(fThenP, [1, 1, 1, 1, 0.3, 0.3, 0.3, 0.3])).changes.single.met,
        isTrue,
      );
      expect(
        DynamicsCheck.of(playedAt(fThenP, [0.3, 0.3, 0.3, 0.3, 1, 1, 1, 1])).changes.single.met,
        isFalse,
      );
    });

    test('Only the player decides what each marking is: a quiet run can still be right', () {
      final check = DynamicsCheck.of(
        playedAt(pThenF, [0.05, 0.05, 0.05, 0.05, 0.12, 0.12, 0.12, 0.12]),
      );
      expect(check.changes.single.met, isTrue);
    });

    test('One marking alone has nothing to be compared with', () {
      final check = DynamicsCheck.of(
        playedAt(quarters([marked(DynamicMark.mf), plain, plain, plain]), [1, 1, 1, 1]),
      );
      expect(check.changes, isEmpty);
      expect(check.hasChecks, isFalse);
    });

    test('Accented notes stand out of their marking and do not set its level', () {
      final score = quarters([
        marked(DynamicMark.p),
        const RhythmEvent(NoteValue.quarter, EventType.accent),
        plain,
        plain,
        marked(DynamicMark.mf),
        plain,
        plain,
        plain,
      ]);
      // A very loud accent in the p bar doesn't make it louder than the mf.
      final check = DynamicsCheck.of(playedAt(score, [0.25, 2, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5]));
      expect(check.changes.single.met, isTrue);
    });

    test('A stretch with nothing played cannot be judged', () {
      final check = DynamicsCheck.of(playedAt(pThenF, [null, null, null, null, 1, 1, 1, 1]));
      expect(check.changes.single.met, isNull);
      expect(check.judged, 0);
    });
  });

  group('Hairpins', () {
    final crescendo = quarters([
      const RhythmEvent(NoteValue.quarter, n, hairpinStart: Hairpin.crescendo),
      plain,
      plain,
      const RhythmEvent(NoteValue.quarter, n, hairpinEnd: true),
    ]);

    test('A crescendo played getting louder is as marked', () {
      final check = DynamicsCheck.of(playedAt(crescendo, [0.2, 0.35, 0.6, 1]));
      expect(check.hairpins.single.changeDb, greaterThan(DynamicsCheck.minChangeDb));
      expect(check.hairpins.single.met, isTrue);
      expect(check.hasChecks, isTrue, reason: 'a hairpin is judged without two markings');
    });

    test('A crescendo played level, or getting softer, is not', () {
      expect(
        DynamicsCheck.of(playedAt(crescendo, [0.5, 0.5, 0.5, 0.5])).hairpins.single.met,
        isFalse,
      );
      expect(
        DynamicsCheck.of(playedAt(crescendo, [1, 0.6, 0.35, 0.2])).hairpins.single.met,
        isFalse,
      );
    });

    test('A decrescendo asks for softer', () {
      final decrescendo = quarters([
        const RhythmEvent(NoteValue.quarter, n, hairpinStart: Hairpin.decrescendo),
        plain,
        plain,
        const RhythmEvent(NoteValue.quarter, n, hairpinEnd: true),
      ]);
      expect(
        DynamicsCheck.of(playedAt(decrescendo, [1, 0.6, 0.35, 0.2])).hairpins.single.met,
        isTrue,
      );
    });

    test('Too few of its notes played to tell', () {
      final check = DynamicsCheck.of(playedAt(crescendo, [0.2, null, null, 1]));
      expect(check.hairpins.single.met, isNull);
    });
  });

  testWidgets('The review lists each check, as marked or not', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final score = quarters([
      marked(DynamicMark.p),
      plain,
      plain,
      plain,
      const RhythmEvent(
        NoteValue.quarter,
        n,
        dynamicMark: DynamicMark.f,
        hairpinStart: Hairpin.decrescendo,
      ),
      plain,
      plain,
      const RhythmEvent(NoteValue.quarter, n, hairpinEnd: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(review: playedAt(score, [0.25, 0.25, 0.25, 0.25, 1, 1, 1, 1])),
      ),
    );

    expect(find.byKey(const Key('review_dynamics')), findsOneWidget);
    expect(find.text('1 of 2 dynamics as marked'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'measure 2: 1\d(\.\d)? dB louder$'), findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Decrescendo, measure 2, notes 1-4: stayed level (should get softer)'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('As marked'), findsOneWidget);
    expect(find.bySemanticsLabel('Not as marked'), findsOneWidget);
  });

  testWidgets('A score without dynamics shows nothing about them', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(review: playedAt(quarters([plain, plain, plain, plain]), [1, 1, 1, 1])),
      ),
    );
    expect(find.byKey(const Key('review_dynamics')), findsNothing);
  });
}
