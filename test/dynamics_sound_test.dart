import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/click_sound.dart';

const n = EventType.normal;
const q = RhythmEvent(NoteValue.quarter, n);

RhythmScore scoreOf(List<RhythmEvent> events) => RhythmScore(
  title: 'Sound',
  tempoBpm: 60,
  measures: [
    for (var start = 0; start < events.length; start += 4)
      Measure(events.sublist(start, start + 4)),
  ],
);

/// [gains] as decibels, rounded to a tenth.
List<double> inDb(List<double> gains) => [
  for (final gain in gains) (200 * math.log(gain) / math.ln10).round() / 10,
];

void main() {
  test('A score without dynamics sounds exactly as before', () {
    expect(ClickSound.dynamicGains(scoreOf([q, q, q, q])), [1, 1, 1, 1]);
  });

  test('Each marking plays at its own level from its note on; before the first, mf', () {
    final score = scoreOf([
      q,
      q.copyWith(dynamicMark: DynamicMark.pp),
      q,
      q.copyWith(dynamicMark: DynamicMark.ff),
    ]);
    expect(inDb(ClickSound.dynamicGains(score)), [0, -12, -12, 8]);
    expect(
      [for (final mark in DynamicMark.values) ClickSound.dynamicDb[mark]],
      [-12, -8, -4, 0, 4, 8],
      reason: 'softest to loudest, 4 dB a step, mf as before',
    );
  });

  test('A crescendo into a marking slides up to it, note by note', () {
    final score = scoreOf([
      q.copyWith(dynamicMark: DynamicMark.p, hairpinStart: Hairpin.crescendo),
      q,
      q,
      q.copyWith(dynamicMark: DynamicMark.f),
    ]);
    expect(inDb(ClickSound.dynamicGains(score)), [-8, -4, 0, 4]);
  });

  test('With nothing to lead into, a hairpin goes two steps, and the level stays there', () {
    final score = scoreOf([
      q.copyWith(dynamicMark: DynamicMark.mf, hairpinStart: Hairpin.decrescendo),
      q,
      q.copyWith(hairpinEnd: true),
      q,
    ]);
    expect(inDb(ClickSound.dynamicGains(score)), [0, -4, -8, -8]);
  });

  test('...but never past pp or ff', () {
    final score = scoreOf([
      q.copyWith(dynamicMark: DynamicMark.f, hairpinStart: Hairpin.crescendo),
      q,
      q,
      q.copyWith(hairpinEnd: true),
    ]);
    expect(inDb(ClickSound.dynamicGains(score)).last, 8);
  });

  test('Mixing turns a sound up or down, but never up past full volume', () {
    final sound = Int16List.fromList([10000, -20000]);
    final buffer = Int32List(4);
    ClickSound.mixInto(buffer, 0, sound, gain: 0.5);
    expect(buffer.sublist(0, 2), [5000, -10000]);

    final loud = Int32List(2);
    ClickSound.mixInto(loud, 0, sound, gain: 4, headroom: ClickSound.headroom(sound));
    expect(loud[1], closeTo(-32767, 1), reason: 'turned up only as far as it has room for');
  });
}
