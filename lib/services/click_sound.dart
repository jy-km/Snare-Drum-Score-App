import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/rhythm_score.dart';

/// Loads and decodes short percussive hit sounds from bundled WAV assets
/// (`assets/audio/<instrument>.wav`), one recording per [Instrument].
///
/// Only one recorded dynamic exists per instrument, so "normal" is the
/// recording attenuated to [_normalGain] and "accent" is the recording as-is
/// -- an amplitude-only approximation of the real dynamic difference a
/// second, harder-hit recording would have, but keeps the asset count to one
/// file per instrument.
class ClickSound {
  static const int sampleRate = 44100;
  static const double _normalGain = 0.5;

  static final Map<Instrument, Future<Int16List>> _rawSamples = {};

  /// Kicks off loading every instrument's sample now, so the first Play
  /// press after app start doesn't pay the asset-load+decode latency.
  static Future<void> preload() => Future.wait(Instrument.values.map(_samplesFor));

  /// Raw mono samples (no WAV header) for [instrument] at normal dynamic,
  /// for mixing into a larger buffer.
  static Future<Int16List> normalSamples(Instrument instrument) async {
    final raw = await _samplesFor(instrument);
    return _scaled(raw, _normalGain);
  }

  /// Raw mono samples (no WAV header) for [instrument] at accent dynamic
  /// (the recording as bundled, unscaled).
  static Future<Int16List> accentSamples(Instrument instrument) => _samplesFor(instrument);

  static Future<Int16List> _samplesFor(Instrument instrument) {
    return _rawSamples.putIfAbsent(instrument, () {
      final future = _loadWav(_assetPath(instrument));
      // A failed load (e.g. called too early, before the widgets binding is
      // ready) would otherwise cache the rejected Future forever, permanently
      // failing every later attempt too. Evict it on failure so a later call
      // gets a fresh attempt; this doesn't swallow the error for whoever is
      // actually awaiting `future` right now.
      future.catchError((Object error, StackTrace stackTrace) {
        _rawSamples.remove(instrument);
        return Future<Int16List>.error(error, stackTrace);
      });
      return future;
    });
  }

  static String _assetPath(Instrument instrument) {
    switch (instrument) {
      case Instrument.kick:
        return 'assets/audio/kick.wav';
      case Instrument.snare:
        return 'assets/audio/snare.wav';
      case Instrument.tambourine:
        return 'assets/audio/tambourine.wav';
    }
  }

  static Future<Int16List> _loadWav(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return _decodeWav(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
  }

  /// Parses a PCM WAV file's `fmt `/`data` chunks (walking past any other
  /// chunk, e.g. the `LIST`/`INFO` metadata chunk these particular files
  /// carry, using each chunk's own declared size rather than assuming a
  /// fixed 44-byte header), decodes 16-bit little-endian samples, and
  /// downmixes to mono if the file is stereo -- this app's mixing/playback
  /// pipeline is mono throughout.
  static Int16List _decodeWav(Uint8List bytes) {
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
        String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    final byteData = ByteData.sublistView(bytes);
    var offset = 12;
    int? numChannels;
    int? fileSampleRate;
    int? bitsPerSample;
    int? dataStart;
    int? dataLength;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes, offset, offset + 4);
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;

      if (chunkId == 'fmt ') {
        numChannels = byteData.getUint16(chunkStart + 2, Endian.little);
        fileSampleRate = byteData.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = byteData.getUint16(chunkStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataStart = chunkStart;
        dataLength = chunkSize;
      }

      // RIFF chunks are padded to an even byte count.
      offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (numChannels == null || dataStart == null || dataLength == null) {
      throw const FormatException('WAV file is missing a fmt or data chunk');
    }
    if (bitsPerSample != 16) {
      throw FormatException('Only 16-bit PCM WAV is supported, got $bitsPerSample-bit');
    }
    if (fileSampleRate != sampleRate) {
      // The mixer/renderer assumes every sample buffer runs at [sampleRate];
      // a file recorded at a different rate would silently play back at the
      // wrong speed/pitch instead of erroring, so fail loudly here instead.
      throw FormatException(
          'Expected a $sampleRate Hz WAV file, got $fileSampleRate Hz -- resample the asset');
    }

    final sampleCount = dataLength ~/ 2;
    final allSamples = Int16List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      allSamples[i] = byteData.getInt16(dataStart + i * 2, Endian.little);
    }

    if (numChannels == 1) return allSamples;

    final frameCount = sampleCount ~/ numChannels;
    final mono = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      var sum = 0;
      for (var channel = 0; channel < numChannels; channel++) {
        sum += allSamples[frame * numChannels + channel];
      }
      mono[frame] = (sum / numChannels).round();
    }
    return mono;
  }

  static Int16List _scaled(Int16List samples, double factor) {
    final scaled = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      scaled[i] = (samples[i] * factor).round().clamp(-32768, 32767);
    }
    return scaled;
  }

  /// Wraps mono 16-bit PCM [samples] in a standard WAV (RIFF) header.
  /// [rate] is the samples' sample rate -- [sampleRate] for everything this
  /// app renders itself; a mic recording may come back at a different one.
  static Uint8List pcm16ToWav(Int16List samples, {int rate = sampleRate}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * 2;
    final byteRate = rate * numChannels * bitsPerSample ~/ 8;
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
    byteData.setUint32(24, rate, Endian.little);
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
