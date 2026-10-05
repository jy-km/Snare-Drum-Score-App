import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/click_sound.dart';
import '../services/onset_detector.dart';

/// Throwaway spike for Milestone 4: records the microphone, runs
/// [OnsetDetector] over the recording, and shows what it found, so the
/// detector can be judged against real hits on a real phone before any
/// practice-mode UI is built around it. Each recording is also saved as a
/// WAV file to pull off the device and turn into a test fixture.
class MicTestScreen extends StatefulWidget {
  const MicTestScreen({super.key});

  @override
  State<MicTestScreen> createState() => _MicTestScreenState();
}

enum _MicTestPhase { idle, recording, analyzing }

class _MicTestScreenState extends State<MicTestScreen> {
  static const _requestedSampleRate = 44100;

  /// Recordings stop themselves here: the whole recording is held in memory
  /// (about 5 MB per minute), and a spike has no use for a longer one.
  static const _maxDuration = Duration(seconds: 60);

  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  StreamSubscription<Uint8List>? _chunkSubscription;
  Timer? _autoStopTimer;
  var _recordedBytes = BytesBuilder(copy: false);
  int _sampleRate = _requestedSampleRate;

  _MicTestPhase _phase = _MicTestPhase.idle;
  double _liveLevel = 0;
  String? _error;
  _Recording? _recording;
  String? _savedPath;
  double _threshold = OnsetAnalysis.defaultThreshold;

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _chunkSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        setState(() => _error = 'Microphone permission was denied. Allow it in the '
            'phone\'s app settings, then try again.');
        return;
      }
      _recordedBytes = BytesBuilder(copy: false);
      _sampleRate = _requestedSampleRate;
      // The phone may not record at exactly the rate asked for; every time
      // below is derived from the sample rate, so it has to be the real one.
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
        ),
      );
      _chunkSubscription = chunks.listen(_onChunk, onDone: _onRecordingClosed, onError: _onError);
    } catch (e) {
      _onError(e);
      return;
    }
    if (!mounted) return;
    _stopwatch
      ..reset()
      ..start();
    _autoStopTimer = Timer(_maxDuration, _stop);
    setState(() {
      _phase = _MicTestPhase.recording;
      _liveLevel = 0;
    });
  }

  void _onChunk(Uint8List chunk) {
    _recordedBytes.add(chunk);
    final data = ByteData.sublistView(chunk);
    var peak = 0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final value = data.getInt16(i, Endian.little).abs();
      if (value > peak) peak = value;
    }
    if (mounted) setState(() => _liveLevel = peak / 32768);
  }

  void _onError(Object error) {
    _autoStopTimer?.cancel();
    _stopwatch.stop();
    if (!mounted) return;
    setState(() {
      _phase = _MicTestPhase.idle;
      _error = 'Recording failed: $error';
    });
  }

  /// Only asks the recorder to stop; the recording is complete once its
  /// stream closes, which is when [_onRecordingClosed] takes over.
  Future<void> _stop() async {
    _autoStopTimer?.cancel();
    _stopwatch.stop();
    try {
      await _recorder.stop();
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _onRecordingClosed() async {
    if (!mounted) return;
    setState(() => _phase = _MicTestPhase.analyzing);

    final bytes = _recordedBytes.takeBytes();
    final sampleRate = _sampleRate;
    try {
      final recording = await compute(_analyzeRecording, (bytes, sampleRate));
      final savedPath = await _saveWav(recording.samples, sampleRate);
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _savedPath = savedPath;
        _phase = _MicTestPhase.idle;
      });
    } catch (e) {
      _onError(e);
    }
  }

  /// Saves to the app's external files folder where there is one (Android),
  /// since that can be copied off the phone without special access.
  Future<String> _saveWav(Int16List samples, int sampleRate) async {
    final baseDir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/mic_tests');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final file = File('${dir.path}/hits_$stamp.wav');
    await file.writeAsBytes(ClickSound.pcm16ToWav(samples, rate: sampleRate));
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    final onsets = recording?.analysis.pickOnsets(threshold: _threshold) ?? const <Onset>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Mic Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Tap Record, play a number of hits you can count, then tap Stop. '
              'The app shows how many hits it heard and where.',
            ),
            const SizedBox(height: 16),
            _buildRecordControls(context),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (recording != null && _phase == _MicTestPhase.idle) ...[
              const SizedBox(height: 24),
              ..._buildResult(context, recording, onsets),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordControls(BuildContext context) {
    switch (_phase) {
      case _MicTestPhase.idle:
        return ElevatedButton.icon(
          key: const Key('mic_test_record_button'),
          onPressed: _start,
          icon: const Icon(Icons.mic),
          label: const Text('Record'),
        );
      case _MicTestPhase.recording:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              key: const Key('mic_test_stop_button'),
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: Text('Stop (${(_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)'),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _liveLevel),
            const SizedBox(height: 4),
            const Text('Input level', textAlign: TextAlign.center),
          ],
        );
      case _MicTestPhase.analyzing:
        return const Center(child: CircularProgressIndicator());
    }
  }

  List<Widget> _buildResult(BuildContext context, _Recording recording, List<Onset> onsets) {
    final textTheme = Theme.of(context).textTheme;
    final warningStyle = TextStyle(color: Theme.of(context).colorScheme.error);
    final peakDb = recording.peak == 0 ? double.negativeInfinity : _toDb(recording.peak);

    return [
      Text(
        '${onsets.length} hits detected',
        key: const Key('mic_test_hit_count'),
        style: textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        '${recording.durationSeconds.toStringAsFixed(1)} s recorded at ${recording.sampleRate} Hz'
        ' · loudest peak ${peakDb.toStringAsFixed(1)} dB',
      ),
      if (recording.clippedSamples > 0)
        Text(
          'The microphone overloaded on ${recording.clippedSamples} samples. '
          'Move the phone further from the instrument.',
          style: warningStyle,
        )
      else if (peakDb < _quietPeakDb)
        Text(
          'This recording is very quiet. Move the phone closer to the instrument.',
          style: warningStyle,
        ),
      const SizedBox(height: 16),
      Text('Threshold: ${(_threshold * 100).round()}% of the strongest hit'),
      Slider(
        key: const Key('mic_test_threshold_slider'),
        value: _threshold,
        min: 0.02,
        max: 0.5,
        divisions: 48,
        onChanged: (value) => setState(() => _threshold = value),
      ),
      const Text('Lower finds quieter hits; higher ignores more noise.'),
      const SizedBox(height: 16),
      const Text('Recording (swipe sideways). Red lines are detected hits.'),
      const SizedBox(height: 4),
      SizedBox(
        height: _WaveformPainter.height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CustomPaint(
            size: Size(recording.columnMax.length.toDouble(), _WaveformPainter.height),
            painter: _WaveformPainter(recording: recording, onsets: onsets),
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (_savedPath != null) ...[
        const Text('Saved to:'),
        SelectableText(_savedPath!, style: textTheme.bodySmall),
        const SizedBox(height: 16),
      ],
      const Text('Hit times (gap since the previous hit):'),
      const SizedBox(height: 4),
      for (var i = 0; i < onsets.length; i++)
        Text(
          '${'${i + 1}'.padLeft(3)}.  ${onsets[i].timeSeconds.toStringAsFixed(3)} s'
          '${i == 0 ? '' : '   +${((onsets[i].timeSeconds - onsets[i - 1].timeSeconds) * 1000).round()} ms'}'
          '   strength ${onsets[i].strength.round()}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
    ];
  }

  /// Below this peak level the mic barely registered anything.
  static const double _quietPeakDb = -40;

  static double _toDb(double amplitude) => 20 * math.log(amplitude) / math.ln10;
}

/// A finished recording plus everything derived from it once, up front.
class _Recording {
  final Int16List samples;
  final int sampleRate;
  final OnsetAnalysis analysis;

  /// Loudest sample as a fraction of full scale (0..1).
  final double peak;

  /// Samples at (or within a hair of) full scale -- the mic overloading.
  final int clippedSamples;

  /// The waveform reduced to one min/max pair per horizontal pixel of
  /// [_WaveformPainter], as fractions of full scale (-1..1).
  final Float32List columnMin;
  final Float32List columnMax;

  _Recording({
    required this.samples,
    required this.sampleRate,
    required this.analysis,
    required this.peak,
    required this.clippedSamples,
    required this.columnMin,
    required this.columnMax,
  });

  double get durationSeconds => samples.length / sampleRate;
}

/// Runs on a background isolate (see `compute`), so the screen stays
/// responsive while a long recording is analyzed.
_Recording _analyzeRecording((Uint8List, int) input) {
  final (bytes, sampleRate) = input;
  final data = ByteData.sublistView(bytes);
  final samples = Int16List(bytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little);
  }

  final samplesPerColumn = sampleRate / _WaveformPainter.pixelsPerSecond;
  final columnCount = (samples.length / samplesPerColumn).ceil();
  final columnMin = Float32List(columnCount);
  final columnMax = Float32List(columnCount);
  var peak = 0;
  var clipped = 0;
  for (var i = 0; i < samples.length; i++) {
    final value = samples[i];
    final magnitude = value.abs();
    if (magnitude > peak) peak = magnitude;
    if (magnitude >= _clipLevel) clipped++;
    final column = i ~/ samplesPerColumn;
    final fraction = value / 32768;
    if (fraction < columnMin[column]) columnMin[column] = fraction;
    if (fraction > columnMax[column]) columnMax[column] = fraction;
  }

  return _Recording(
    samples: samples,
    sampleRate: sampleRate,
    analysis: OnsetDetector.analyze(samples, sampleRate: sampleRate),
    peak: peak / 32768,
    clippedSamples: clipped,
    columnMin: columnMin,
    columnMax: columnMax,
  );
}

const int _clipLevel = 32760;

class _WaveformPainter extends CustomPainter {
  static const double height = 140;
  static const double pixelsPerSecond = 150;
  static const double _labelHeight = 16;

  final _Recording recording;
  final List<Onset> onsets;

  _WaveformPainter({required this.recording, required this.onsets});

  @override
  void paint(Canvas canvas, Size size) {
    final waveHeight = size.height - _labelHeight;
    final centerY = waveHeight / 2;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, waveHeight),
      Paint()..color = Colors.black.withValues(alpha: 0.04),
    );

    final gridPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    for (var second = 0; second * pixelsPerSecond <= size.width; second++) {
      final x = second * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, waveHeight), gridPaint);
      final label = TextPainter(
        text: TextSpan(
          text: '${second}s',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 2, waveHeight + 2));
    }

    final wavePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1;
    for (var column = 0; column < recording.columnMax.length; column++) {
      final x = column + 0.5;
      canvas.drawLine(
        Offset(x, centerY - recording.columnMax[column] * centerY),
        // At least a pixel tall, so silence still shows as a center line.
        Offset(x, centerY - recording.columnMin[column] * centerY + 1),
        wavePaint,
      );
    }

    final onsetPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5;
    for (final onset in onsets) {
      final x = onset.timeSeconds * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, waveHeight), onsetPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.recording != recording || oldDelegate.onsets != onsets;
}
