import 'dart:math' as math;
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
/// file per instrument. "Marcato" is the recording turned up by as much of
/// [_marcatoGain] as it has room for before clipping, and a grace stroke (of
/// a flam or drag) is the recording at [_graceGain]. Dynamics written in
/// the score turn each note up or down from there ([dynamicGains]).
class ClickSound {
  static const int sampleRate = 44100;
  static const double _normalGain = 0.5;
  static const double _marcatoGain = 1.4;
  static const double _graceGain = 0.25;

  /// How long before its note a flam's grace stroke sounds, and how far
  /// apart a drag's two are.
  static const double _graceSpacingMs = 30;

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

  /// Samples for [instrument] at marcato dynamic: louder than the accent by
  /// up to [_marcatoGain], less where the recording is already near full
  /// volume (the kick's is at it, so its marcato sounds like its accent).
  static Future<Int16List> marcatoSamples(Instrument instrument) async {
    final raw = await _samplesFor(instrument);
    final room = headroom(raw);
    return _scaled(raw, room < _marcatoGain ? room : _marcatoGain);
  }

  /// Samples for one grace stroke of a flam or drag on [instrument].
  static Future<Int16List> graceSamples(Instrument instrument) async {
    final raw = await _samplesFor(instrument);
    return _scaled(raw, _graceGain);
  }

  /// The samples a note of [type] sounds with, out of the three dynamics.
  static Int16List samplesForType(
    EventType type, {
    required Int16List normal,
    required Int16List accent,
    required Int16List marcato,
  }) {
    switch (type) {
      case EventType.marcato:
        return marcato;
      case EventType.accent:
        return accent;
      case EventType.rest:
      case EventType.normal:
        return normal;
    }
  }

  /// How much louder (positive) or softer than its plain sound each marking
  /// plays, in decibels -- mf is the sound as it has always been, and each
  /// step either side is 4 dB. My choice, to tune by ear.
  static const Map<DynamicMark, double> dynamicDb = {
    DynamicMark.pp: -12,
    DynamicMark.p: -8,
    DynamicMark.mp: -4,
    DynamicMark.mf: 0,
    DynamicMark.f: 4,
    DynamicMark.ff: 8,
  };

  /// How far a hairpin with no marking to lead into goes: two steps.
  static const double _hairpinWithoutTargetDb = 8;

  /// How loud each note of [score] plays, as a factor on its sound (1 for
  /// as it has always been), by note index. Notes before the first marking
  /// play at mf. A hairpin slides, in decibels, from the level at its first
  /// note to the marking it leads into -- or, with none, two steps up or
  /// down -- by where each note falls in it; the level it reaches holds
  /// until the next marking. A score without dynamics is all 1s.
  static List<double> dynamicGains(RhythmScore score) {
    final notes = score.notes;
    final starts = score.noteStartUnits;
    final db = List<double>.filled(notes.length, 0);
    final spans = {for (final span in score.hairpinSpans) span.firstNote: span};
    var current = 0.0;
    var note = 0;
    while (note < notes.length) {
      final mark = notes[note].dynamicMark;
      if (mark != null) current = dynamicDb[mark]!;
      final span = spans[note];
      if (span == null || span.lastNote == note) {
        db[note] = current;
        note++;
        continue;
      }
      final target = notes[span.lastNote].dynamicMark;
      final up = span.kind == Hairpin.crescendo;
      final end = target != null
          ? dynamicDb[target]!
          : (current + (up ? 1 : -1) * _hairpinWithoutTargetDb).clamp(
              dynamicDb[DynamicMark.pp]!,
              dynamicDb[DynamicMark.ff]!,
            );
      final from = starts[span.firstNote];
      final length = starts[span.lastNote] - from;
      for (var index = span.firstNote; index <= span.lastNote; index++) {
        db[index] = current + (end - current) * (starts[index] - from) / length;
      }
      current = end;
      note = span.lastNote + 1;
    }
    return [for (final level in db) level == 0 ? 1.0 : _gainFor(level)];
  }

  static double _gainFor(double db) => math.pow(10, db / 20).toDouble();

  /// The most [samples] can be turned up without clipping.
  static double headroom(Int16List samples) {
    var peak = 1;
    for (final sample in samples) {
      if (sample.abs() > peak) peak = sample.abs();
    }
    return 32767 / peak;
  }

  /// Adds [samples], turned up or down by [gain] -- but no further up than
  /// [headroom] allows -- into [buffer] from [start] on.
  static void mixInto(
    Int32List buffer,
    int start,
    Int16List samples, {
    double gain = 1,
    double headroom = double.infinity,
  }) {
    final factor = gain > headroom ? headroom : gain;
    if (factor == 1) {
      for (var i = 0; i < samples.length; i++) {
        buffer[start + i] += samples[i];
      }
      return;
    }
    for (var i = 0; i < samples.length; i++) {
      buffer[start + i] += (samples[i] * factor).round();
    }
  }

  /// Where the strokes of a rolled note fall after its first one, in
  /// [RhythmGrid] units from the start of the note: one every sixteenth for
  /// as long as the note lasts (a rolled quarter is four strokes in all).
  /// Empty for a note that isn't a roll, or is too short to hold a second
  /// stroke. A stand-in until there is a recorded roll to play instead.
  static List<int> rollStrokeUnits(RhythmEvent event) {
    if (event.ornament != Ornament.roll) return const [];
    final spacing = NoteValue.sixteenth.units;
    return [
      for (var units = spacing; units + spacing <= event.durationUnits; units += spacing) units,
    ];
  }

  /// How many samples before its note each grace stroke of [ornament]
  /// starts, earliest first, at [msPerUnit] per [RhythmGrid] unit. The
  /// strokes close up at fast tempos so they never reach back further than
  /// a sixteenth note.
  static List<int> graceLeadSamples(Ornament ornament, double msPerUnit) {
    final count = ornament.graceNoteCount;
    if (count == 0) return const [];
    final longestLeadMs = NoteValue.sixteenth.units * msPerUnit;
    final spacingMs = _graceSpacingMs * count > longestLeadMs
        ? longestLeadMs / count
        : _graceSpacingMs;
    return [
      for (var stroke = count; stroke >= 1; stroke--)
        (stroke * spacingMs * sampleRate / 1000).round(),
    ];
  }

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
        'Expected a $sampleRate Hz WAV file, got $fileSampleRate Hz -- resample the asset',
      );
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
