import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/click_sound.dart';
import 'package:snare_drum_score_app/services/onset_detector.dart';

const _sampleRate = ClickSound.sampleRate;

/// Builds a recording of [hit] played at each of [hitTimes] (seconds) with
/// the matching entry of [gains], over steady background noise -- a stand-in
/// for a real mic recording where the true hit times are known exactly.
Int16List _synthesize(
  Int16List hit, {
  required List<double> hitTimes,
  required List<double> gains,
  double durationSeconds = 3,
  double noiseAmplitude = 40,
}) {
  final mix = Float64List((durationSeconds * _sampleRate).round());
  final random = math.Random(1);
  for (var i = 0; i < mix.length; i++) {
    mix[i] = (random.nextDouble() * 2 - 1) * noiseAmplitude;
  }
  for (var h = 0; h < hitTimes.length; h++) {
    final start = (hitTimes[h] * _sampleRate).round();
    for (var i = 0; i < hit.length && start + i < mix.length; i++) {
      mix[start + i] += hit[i] * gains[h];
    }
  }
  final samples = Int16List(mix.length);
  for (var i = 0; i < mix.length; i++) {
    samples[i] = mix[i].round().clamp(-32768, 32767);
  }
  return samples;
}

/// Asserts [onsets] has exactly one onset per entry of [hitTimes], each
/// within [toleranceSeconds] of it.
void _expectOnsetsAt(List<Onset> onsets, List<double> hitTimes, {double toleranceSeconds = 0.008}) {
  expect(onsets.length, equals(hitTimes.length), reason: 'detected: $onsets');
  for (var i = 0; i < hitTimes.length; i++) {
    expect(onsets[i].timeSeconds, closeTo(hitTimes[i], toleranceSeconds), reason: 'hit ${i + 1}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final instrument in Instrument.values) {
    test('Finds every ${instrument.name} hit at 10 per second, alternating loud and soft',
        () async {
      final hit = await ClickSound.accentSamples(instrument);
      final hitTimes = [for (var i = 0; i < 16; i++) 0.5 + i * 0.1];
      final gains = [for (var i = 0; i < 16; i++) i.isEven ? 0.6 : 0.3];

      final onsets = OnsetDetector.detect(
        _synthesize(hit, hitTimes: hitTimes, gains: gains),
        sampleRate: _sampleRate,
      );

      _expectOnsetsAt(onsets, hitTimes);
    });
  }

  test('Finds quiet ghost notes between much louder accents', () async {
    // Ghosts 18 dB below the accents, each played while the previous
    // accent's tail (this snare sample rings for over 3 seconds) is still
    // sounding. At 24 dB below (gain 0.05) the default threshold starts
    // missing some -- that is the detector's current limit, not a goal.
    final hit = await ClickSound.accentSamples(Instrument.snare);
    final hitTimes = [for (var i = 0; i < 8; i++) 0.5 + i * 0.25];
    final gains = [for (var i = 0; i < 8; i++) i.isEven ? 0.8 : 0.1];

    final onsets = OnsetDetector.detect(
      _synthesize(hit, hitTimes: hitTimes, gains: gains),
      sampleRate: _sampleRate,
    );

    _expectOnsetsAt(onsets, hitTimes);
  });

  test('Finds hits in a recording that is quiet overall', () async {
    final hit = await ClickSound.accentSamples(Instrument.snare);
    final hitTimes = [0.5, 1.0, 1.5, 2.0];

    final onsets = OnsetDetector.detect(
      _synthesize(hit, hitTimes: hitTimes, gains: List.filled(4, 0.03), noiseAmplitude: 10),
      sampleRate: _sampleRate,
    );

    _expectOnsetsAt(onsets, hitTimes);
  });

  test('Reports nothing for background noise alone', () {
    final noise = _synthesize(Int16List(0), hitTimes: const [], gains: const []);
    expect(OnsetDetector.detect(noise, sampleRate: _sampleRate), isEmpty);

    final loudNoise = _synthesize(
      Int16List(0),
      hitTimes: const [],
      gains: const [],
      noiseAmplitude: 600,
    );
    expect(OnsetDetector.detect(loudNoise, sampleRate: _sampleRate), isEmpty);
  });

  test('Reports nothing for an empty or too-short recording', () {
    expect(OnsetDetector.detect(Int16List(0), sampleRate: _sampleRate), isEmpty);
    expect(OnsetDetector.detect(Int16List(100), sampleRate: _sampleRate), isEmpty);
  });

  test('A higher threshold drops the quietest hits', () async {
    final hit = await ClickSound.accentSamples(Instrument.snare);
    final analysis = OnsetDetector.analyze(
      _synthesize(hit, hitTimes: const [0.5, 1.0, 1.5], gains: const [0.8, 0.02, 0.8]),
      sampleRate: _sampleRate,
    );

    expect(analysis.pickOnsets().length, equals(3));
    expect(analysis.pickOnsets(threshold: 0.8).length, equals(2));
  });
}
