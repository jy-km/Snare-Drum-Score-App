import 'dart:math' as math;
import 'dart:typed_data';

const synthSampleRate = 44100;

/// A stand-in for a microphone recording: [seconds] of faint background
/// noise with a short percussive burst (a decaying crack of noise, roughly a
/// stick on a pad) starting at each of [hitTimes].
Int16List synthRecording({required double seconds, required List<double> hitTimes}) {
  final random = math.Random(7);
  final mix = Float64List((seconds * synthSampleRate).round());
  for (var i = 0; i < mix.length; i++) {
    mix[i] = (random.nextDouble() * 2 - 1) * 20;
  }
  const burstSeconds = 0.06;
  const decaySeconds = 0.01;
  for (final hitTime in hitTimes) {
    final start = (hitTime * synthSampleRate).round();
    final length = (burstSeconds * synthSampleRate).round();
    for (var i = 0; i < length && start + i < mix.length; i++) {
      final envelope = math.exp(-i / synthSampleRate / decaySeconds);
      mix[start + i] += (random.nextDouble() * 2 - 1) * 12000 * envelope;
    }
  }
  final samples = Int16List(mix.length);
  for (var i = 0; i < mix.length; i++) {
    samples[i] = mix[i].round().clamp(-32768, 32767);
  }
  return samples;
}

/// The part of [recording] between two times, as a microphone would deliver
/// it in one chunk.
Int16List synthSlice(Int16List recording, double fromSeconds, double toSeconds) {
  final from = (fromSeconds * synthSampleRate).round();
  final to = math.min(recording.length, (toSeconds * synthSampleRate).round());
  return Int16List.sublistView(recording, from, to);
}
