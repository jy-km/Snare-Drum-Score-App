import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// A live microphone, as mono 16-bit samples. An interface so screens can be
/// tested with canned audio instead of a real device microphone.
abstract class MicInput {
  /// Asks the user for microphone access if they haven't answered yet.
  /// Returns whether the microphone may be used.
  Future<bool> requestPermission();

  /// Starts listening. The stream delivers audio in the order it was heard,
  /// in chunks of whatever size the device produces.
  Future<Stream<Int16List>> start();

  /// Samples per second of the audio from [start]. Only meaningful once
  /// [start] has completed.
  int get sampleRate;

  Future<void> stop();
}

/// Works out the wall-clock moment a microphone stream's audio begins, from
/// when each chunk of it arrives -- which is what lets a moment on the
/// app's clock (e.g. "the count-in started playing now") be found in the
/// recording.
///
/// A chunk can only arrive after it was recorded, never before, so of all
/// the "arrival time minus audio delivered so far" seen, the earliest is
/// the closest to the truth; the estimate only ever improves.
class RecordingClock {
  DateTime? _start;
  int _samplesReceived = 0;

  /// Call as each chunk arrives, with how many samples it held.
  void addChunk(int sampleCount, int sampleRate) {
    _samplesReceived += sampleCount;
    final audioSoFar = Duration(microseconds: (_samplesReceived * 1e6 / sampleRate).round());
    final startIfJustRecorded = clock.now().subtract(audioSoFar);
    final start = _start;
    if (start == null || startIfJustRecorded.isBefore(start)) _start = startIfJustRecorded;
  }

  /// How far into the recording [moment] falls, in seconds -- null until
  /// the first chunk has arrived.
  double? secondsAt(DateTime moment) {
    final start = _start;
    return start == null ? null : moment.difference(start).inMicroseconds / 1e6;
  }
}

/// The device's real microphone.
class DeviceMicInput implements MicInput {
  static const _requestedSampleRate = 44100;

  final _recorder = AudioRecorder();
  int _sampleRate = _requestedSampleRate;

  @override
  int get sampleRate => _sampleRate;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Int16List>> start() async {
    // The phone may not record at exactly the rate asked for.
    await _recorder.setOnConfigChanged((config) => _sampleRate = config.sampleRate);
    final chunks = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _requestedSampleRate,
        numChannels: 1,
        // The raw microphone signal, without the phone's voice-call
        // processing: automatic gain and noise suppression are built to
        // flatten exactly the sudden loud transients a drum hit is.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.unprocessed),
        // The default pauses recording whenever another sound takes over
        // the phone's audio output -- which this app's own count-in and
        // rhythm playback do, every time, while the mic is listening.
        audioInterruption: AudioInterruptionMode.none,
      ),
    );
    return chunks.map(_toSamples);
  }

  static Int16List _toSamples(Uint8List bytes) {
    if (bytes.length.isOdd) {
      debugPrint('Mic chunk had an odd byte count (${bytes.length}); dropping the last byte');
    }
    final data = ByteData.sublistView(bytes);
    final samples = Int16List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
    await _recorder.dispose();
  }
}
