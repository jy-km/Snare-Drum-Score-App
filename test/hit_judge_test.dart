import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/hit_judge.dart';

void main() {
  test('Judgement depends on how far the hit is from its note, early or late', () {
    // A hit too far off isn't paired with the note at all, so the note ends
    // up a miss.
    Judgement judge(double offsetSeconds) {
      final judge = HitJudge([10.0]);
      return judge.addHit(10.0 + offsetSeconds)?.judgement ?? judge.finish().single.judgement;
    }

    expect(judge(0), Judgement.perfect);
    expect(judge(0.039), Judgement.perfect);
    expect(judge(-0.039), Judgement.perfect);
    expect(judge(0.041), Judgement.great);
    expect(judge(-0.079), Judgement.great);
    expect(judge(0.081), Judgement.good);
    expect(judge(-0.119), Judgement.good);
    expect(judge(0.121), Judgement.miss);
    expect(judge(-0.121), Judgement.miss);
  });

  test('A matched hit reports its note and its signed offset', () {
    final judge = HitJudge([1.0, 2.0]);

    final late = judge.addHit(1.05)!;
    expect(late.noteIndex, 0);
    expect(late.offsetSeconds, closeTo(0.05, 1e-9));

    final early = judge.addHit(1.97)!;
    expect(early.noteIndex, 1);
    expect(early.offsetSeconds, closeTo(-0.03, 1e-9));
  });

  test('A hit with no note nearby is not judged', () {
    final judge = HitJudge([1.0]);

    expect(judge.addHit(1.5), isNull);
    expect(judge.counts.values.reduce((a, b) => a + b), 0);
  });

  test('A second hit on a note keeps the first hit\'s judgement and adds none', () {
    final judge = HitJudge([1.0, 2.0]);

    expect(judge.addHit(1.0)!.judgement, Judgement.perfect);
    // Even when the second hit would have been a better (or worse) one.
    expect(judge.addHit(1.03), isNull);
    expect(judge.addHit(1.1), isNull);

    judge.finish();
    expect(judge.counts, {
      Judgement.perfect: 1,
      Judgement.great: 0,
      Judgement.good: 0,
      Judgement.miss: 1, // the note at 2.0, never hit
      Judgement.fail: 0, // no rests given, so nothing can fail
    });
  });

  test('A note keeps its earliest judgement, even when a closer hit follows', () {
    final judge = HitJudge([1.0]);

    expect(judge.addHit(0.9)!.judgement, Judgement.good);
    expect(judge.addHit(1.0), isNull);

    expect(judge.finish(), isEmpty);
    expect(judge.counts[Judgement.good], 1);
    expect(judge.counts[Judgement.perfect], 0);
  });

  test('A note that was hit is never also judged a miss', () {
    final judge = HitJudge([1.0]);
    judge.addHit(1.0);

    expect(judge.advanceTo(5.0), isEmpty);
    expect(judge.finish(), isEmpty);
    expect(judge.counts[Judgement.miss], 0);
  });

  test('A note becomes a miss only once its Good window has passed', () {
    final judge = HitJudge([1.0, 2.0]);

    expect(judge.advanceTo(1.1), isEmpty);

    final misses = judge.advanceTo(1.13);
    expect(misses.single.judgement, Judgement.miss);
    expect(misses.single.noteIndex, 0);
    expect(misses.single.offsetSeconds, isNull);

    // Already settled: not reported again.
    expect(judge.advanceTo(1.5), isEmpty);
  });

  test('Notes 100ms apart each take their own hit', () {
    // 10 notes per second: every hit is within the Good window of its
    // neighbours' notes too, so pairing has to go by nearest.
    final noteTimes = [for (var i = 0; i < 8; i++) 1.0 + i * 0.1];
    final judge = HitJudge(noteTimes);

    final judged = [for (final time in noteTimes) judge.addHit(time + 0.01)!];

    expect(judged.map((j) => j.noteIndex), [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(judged.every((j) => j.judgement == Judgement.perfect), isTrue);
  });

  test('Skipping a note misses that note, not the ones after it', () {
    final judge = HitJudge([1.0, 1.1, 1.2]);

    expect(judge.addHit(1.0)!.noteIndex, 0);
    expect(judge.addHit(1.2)!.noteIndex, 2);

    expect(judge.finish().single.noteIndex, 1);
  });

  test('Counts tally one judgement per note, with stray hits counted nowhere', () {
    final judge = HitJudge([1.0, 2.0, 3.0, 4.0]);
    judge.addHit(1.0); // perfect
    judge.addHit(1.02); // second hit on the first note
    judge.addHit(2.06); // great
    judge.addHit(2.5); // nowhere near a note
    judge.addHit(3.1); // good
    judge.finish(); // note at 4.0 never hit

    expect(judge.counts, {
      Judgement.perfect: 1,
      Judgement.great: 1,
      Judgement.good: 1,
      Judgement.miss: 1,
      Judgement.fail: 0, // no rests given, so the stray at 2.5 fails nothing
    });
  });

  test('However messy the playing, every note is judged exactly once', () {
    final random = math.Random(3);
    // 10 notes per second, the densest the app supports.
    final noteTimes = [for (var i = 0; i < 40; i++) 1.0 + i * 0.1];
    for (var trial = 0; trial < 50; trial++) {
      final judge = HitJudge(noteTimes);
      // Hits that skip notes, double up, rush, drag, and wander off.
      final hitTimes = <double>[
        for (final time in noteTimes)
          for (var copy = random.nextInt(3); copy > 0; copy--)
            time + (random.nextDouble() - 0.5) * 0.3,
        for (var i = 0; i < 10; i++) random.nextDouble() * 6,
      ]..sort();

      final judged = <JudgedHit>[];
      for (final time in hitTimes) {
        judged.addAll(judge.advanceTo(time));
        final hit = judge.addHit(time);
        if (hit != null) judged.add(hit);
      }
      judged.addAll(judge.finish());

      expect(
        judged.map((j) => j.noteIndex).toList()..sort(),
        [for (var i = 0; i < noteTimes.length; i++) i],
        reason: 'trial $trial',
      );
      expect(judge.counts.values.reduce((a, b) => a + b), noteTimes.length);
    }
  });

  group('Fail', () {
    // Quarter notes at 1s and 3s, with a rest from 1.5s to 3s between them
    // (a quarter at 60 BPM lasts 1s; here the first is followed by a half
    // second of note and then rest).
    const rest = (1.5, 3.0);

    test('A hit during a rest is a fail', () {
      final judge = HitJudge([1.0, 3.0], rests: [rest]);

      final hit = judge.addHit(2.2)!;

      expect(hit.judgement, Judgement.fail);
      expect(hit.noteIndex, isNull);
      expect(hit.offsetSeconds, isNull);
      expect(hit.hitTimeSeconds, 2.2);
    });

    test('Has no timing window: anywhere in the rest fails, however far from a note', () {
      final judge = HitJudge([1.0, 10.0], rests: [(1.5, 10.0)]);

      for (final time in [1.5, 2.0, 5.0, 9.0]) {
        expect(judge.addHit(time)!.judgement, Judgement.fail, reason: 'at ${time}s');
      }
      expect(judge.counts[Judgement.fail], 4);
    });

    test('A hit that can be paired with a note is that note\'s, even inside a rest', () {
      final judge = HitJudge([1.0, 3.0], rests: [rest]);

      // 100ms early for the note after the rest.
      expect(judge.addHit(2.9)!.judgement, Judgement.good);
      expect(judge.counts[Judgement.fail], 0);
    });

    test('A repeat hit that spills into a rest fails; one while the note sounds does not', () {
      final judge = HitJudge([1.0, 3.0], rests: [rest]);

      expect(judge.addHit(1.0)!.judgement, Judgement.perfect);
      expect(judge.addHit(1.1), isNull, reason: 'still within the note, not a rest');
      expect(judge.addHit(1.6)!.judgement, Judgement.fail);
    });

    test('A fail never changes a note\'s judgement', () {
      final judge = HitJudge([1.0, 3.0], rests: [rest]);
      judge.addHit(2.0); // fail
      judge.addHit(3.0); // the note after the rest, on time

      judge.finish();
      expect(judge.counts, {
        Judgement.perfect: 1,
        Judgement.great: 0,
        Judgement.good: 0,
        Judgement.miss: 1, // the note at 1.0, never hit
        Judgement.fail: 1,
      });
    });

    test('Fails do not count toward the one-judgement-per-note total', () {
      final noteTimes = [1.0, 2.0, 3.0, 4.0];
      final judge = HitJudge(noteTimes, rests: [(1.25, 2.0), (2.25, 3.0), (3.25, 4.0)]);
      for (final time in [1.0, 1.5, 1.6, 2.0, 2.5, 3.0, 3.5, 4.0]) {
        judge.advanceTo(time);
        judge.addHit(time);
      }
      judge.finish();

      final noteJudgements = [
        for (final entry in judge.counts.entries)
          if (entry.key.judgesANote) entry.value,
      ].reduce((a, b) => a + b);
      expect(noteJudgements, noteTimes.length);
      expect(judge.counts[Judgement.fail], 4);
    });

    test('A stray hit outside every rest is still not judged', () {
      final judge = HitJudge([1.0], rests: [rest]);

      expect(judge.addHit(0.5), isNull);
      expect(judge.addHit(3.5), isNull, reason: 'after the rest has ended');
    });
  });
}
