import 'dart:async';
import 'dart:typed_data';

import 'package:snare_drum_score_app/services/mic_input.dart';
import 'package:snare_drum_score_app/services/mic_latency.dart';

import 'synth_audio.dart';

/// A microphone that hears only what the test feeds it.
class FakeMicInput implements MicInput {
  final _controller = StreamController<Int16List>();
  bool permissionGranted = true;
  bool started = false;
  bool stopped = false;

  void hear(Int16List samples) => _controller.add(samples);

  @override
  int get sampleRate => synthSampleRate;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<Stream<Int16List>> start() async {
    started = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;
}

/// Remembers the sound delay only for as long as the test runs.
class FakeMicLatencyStore implements MicLatencyStore {
  MicLatencyHistory history;

  FakeMicLatencyStore([List<double> measurements = const []])
      : history = MicLatencyHistory(measurements);

  @override
  Future<MicLatencyHistory> load() async => history;

  @override
  Future<void> save(MicLatencyHistory history) async => this.history = history;
}

/// Remembers the calibration only for as long as the test runs.
class FakeMicCalibrationStore implements MicCalibrationStore {
  double? offsetSeconds;

  FakeMicCalibrationStore([this.offsetSeconds]);

  @override
  Future<double?> load() async => offsetSeconds;

  @override
  Future<void> save(double? offsetSeconds) async => this.offsetSeconds = offsetSeconds;
}
