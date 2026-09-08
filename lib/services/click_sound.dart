import 'dart:math';
import 'dart:typed_data';

/// Synthesizes short percussive click sounds in-app (rather than bundling an
/// audio sample), so verification playback needs no external asset.
class ClickSound {
  static const int sampleRate = 44100;
  static const double _durationSeconds = 0.08;

  /// Raw mono samples (no WAV header), for mixing into a larger buffer.
  static final Int16List normalClickSamples = _synthesize(peakAmplitude: 0.5);
  static final Int16List accentClickSamples = _synthesize(peakAmplitude: 1.0);

  static Int16List _synthesize({required double peakAmplitude}) {
    final sampleCount = (sampleRate * _durationSeconds).round();
    final samples = Int16List(sampleCount);
    final random = Random(7);

    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final envelope = exp(-t * 40);
      final noise = random.nextDouble() * 2 - 1;
      final tone = sin(2 * pi * 180 * t) * 0.3;
      final sample = ((noise * 0.7 + tone) * envelope * peakAmplitude).clamp(-1.0, 1.0);
      samples[i] = (sample * 32767).round();
    }

    return samples;
  }

  /// Wraps mono 16-bit PCM [samples] in a standard WAV (RIFF) header.
  static Uint8List pcm16ToWav(Int16List samples) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * 2;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;

    final byteData = ByteData(44 + dataSize);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        byteData.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    byteData.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      byteData.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return byteData.buffer.asUint8List();
  }
}
