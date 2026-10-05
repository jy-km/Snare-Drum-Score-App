import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/click_sound.dart';
import '../services/mic_input.dart';
import '../services/mic_latency.dart';
import '../services/onset_detector.dart';
import '../services/tap_calibration.dart';

enum _CalibrationPhase { idle, running, done }

/// Calibration mode: a steady beat plays, the player plays along on their
/// instrument, and the average distance between each beat (as the app's
/// clock has it) and the hit heard for it is saved as the input offset --
/// see [TapCalibration] for what that distance consists of and
/// `PracticeScreen` for how it is used.
///
/// The input is the microphone hearing the instrument, not a tap on the
/// screen, because that is the input practice mode judges: a screen tap
/// would measure the touchscreen's delay, which no practice run ever sees.
class CalibrationScreen extends StatefulWidget {
  final MicInput Function() createMicInput;
  final MicCalibrationStore store;

  const CalibrationScreen({
    super.key,
    this.createMicInput = DeviceMicInput.new,
    this.store = const FileMicCalibrationStore(),
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  static const _tempoBpm = 120;
  static const _beatSeconds = 60 / _tempoBpm;
  static const _instrument = Instrument.tambourine;

  /// The first beats are for the player to find the pulse; only hits from
  /// the beat after them on are measured.
  static const _settleBeats = 4;
  static const _totalBeats = 20;
  static const _totalSeconds = _totalBeats * _beatSeconds;

  /// A hit may come this far ahead of the first measured beat and still be
  /// taken as a hit on it.
  static const _earlyAllowanceSeconds = 0.1;

  /// See `PracticeScreen`'s identically named constants: the beat's audio
  /// reports position 0 while it is still starting up, and if it never
  /// reports a position at all the run goes ahead on the clock alone.
  static const _minStartupPosition = Duration(milliseconds: 20);
  static const _audioFallbackDelay = Duration(milliseconds: 1000);

  /// How long after the last beat to keep listening: a hit on it is only
  /// reported once the audio after it has arrived and been analyzed.
  static const _tailDelay = Duration(milliseconds: 400);

  final _player = AudioPlayer(playerId: 'calibration_beat');
  late final AnimationController _progress;

  MicInput? _mic;
  StreamSubscription<Int16List>? _micSubscription;
  StreamingOnsetDetector? _detector;
  RecordingClock _recordingClock = RecordingClock();

  /// Every hit heard this run, in seconds from the start of the recording.
  final _hitTimes = <double>[];

  StreamSubscription<Duration>? _positionSubscription;
  Timer? _audioFallbackTimer;
  Timer? _tailTimer;

  /// The wall-clock moment the beat's audio reported starting.
  DateTime? _beatAnchor;

  _CalibrationPhase _phase = _CalibrationPhase.idle;
  bool _starting = false;
  String? _error;
  CalibrationOutcome? _outcome;
  double? _savedOffsetSeconds;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_totalSeconds * 1000).round()),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _tailTimer = Timer(_tailDelay, _finish);
      });
    unawaited(_loadSaved());
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await widget.store.load();
      if (mounted) setState(() => _savedOffsetSeconds = saved);
    } catch (e) {
      debugPrint('Could not load the saved calibration: $e');
    }
  }

  @override
  void dispose() {
    _stopListening();
    _progress.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() {
      _error = null;
      _outcome = null;
    });

    final mic = widget.createMicInput();
    try {
      if (!await mic.requestPermission()) {
        _releaseMic(mic);
        if (mounted) {
          setState(() => _error = 'Microphone permission was denied. Allow it in the '
              'phone\'s app settings, then try again.');
        }
        return;
      }
      final chunks = await mic.start();
      if (!mounted) {
        _releaseMic(mic);
        return;
      }
      _mic = mic;
      _detector = StreamingOnsetDetector(sampleRate: mic.sampleRate);
      _recordingClock = RecordingClock();
      _hitTimes.clear();
      _micSubscription = chunks.listen(
        _onMicSamples,
        onError: (Object e) => debugPrint('Calibration microphone stream failed: $e'),
      );
    } catch (e) {
      _releaseMic(mic);
      if (mounted) setState(() => _error = 'Could not start the microphone: $e');
      return;
    } finally {
      _starting = false;
    }

    setState(() => _phase = _CalibrationPhase.running);
    _beatAnchor = null;
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (_beatAnchor != null || position < _minStartupPosition) return;
      _beginBeat(clock.now().subtract(position));
    });
    unawaited(_playBeat());
    _audioFallbackTimer = Timer(_audioFallbackDelay, () {
      if (_beatAnchor == null) _beginBeat(clock.now());
    });
  }

  /// Renders the whole run's beat into one buffer and plays it once, like
  /// every other sound in this app -- see `RhythmPlayer` for why.
  Future<void> _playBeat() async {
    try {
      final hit = await ClickSound.accentSamples(_instrument);
      final samplesPerBeat = ClickSound.sampleRate * _beatSeconds;
      final mix = Int16List((_totalBeats * samplesPerBeat).ceil() + hit.length);
      for (var beat = 0; beat < _totalBeats; beat++) {
        final start = (beat * samplesPerBeat).round();
        for (var i = 0; i < hit.length; i++) {
          mix[start + i] = (mix[start + i] + hit[i]).clamp(-32768, 32767);
        }
      }
      await _player.play(BytesSource(ClickSound.pcm16ToWav(mix)));
    } catch (e) {
      debugPrint('Calibration beat failed to play: $e');
    }
  }

  void _beginBeat(DateTime anchor) {
    _beatAnchor = anchor;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _audioFallbackTimer?.cancel();
    _audioFallbackTimer = null;
    final elapsed = clock.now().difference(anchor);
    _progress.forward(
      from: (elapsed.inMicroseconds / _progress.duration!.inMicroseconds).clamp(0.0, 1.0),
    );
  }

  void _onMicSamples(Int16List samples) {
    final detector = _detector;
    final mic = _mic;
    if (detector == null || mic == null) return;
    _recordingClock.addChunk(samples.length, mic.sampleRate);
    final onsets = detector.addSamples(samples);
    if (onsets.isEmpty) return;
    setState(() => _hitTimes.addAll(onsets.map((onset) => onset.timeSeconds)));
  }

  /// Averages the run's hits into an offset and, if the run was good enough
  /// to trust, saves it.
  void _finish() {
    final anchor = _beatAnchor;
    final beatStart = anchor == null ? null : _recordingClock.secondsAt(anchor);
    _stopListening();
    if (beatStart == null) {
      setState(() {
        _phase = _CalibrationPhase.idle;
        _error = 'No sound reached the microphone. Try again.';
      });
      return;
    }

    final outcome = TapCalibration.measure(
      hitTimes: [for (final time in _hitTimes) time - beatStart],
      beatSeconds: _beatSeconds,
      fromSeconds: _settleBeats * _beatSeconds - _earlyAllowanceSeconds,
    );
    final offset = outcome.offsetSeconds;
    if (offset != null) unawaited(_save(offset));
    setState(() {
      _phase = _CalibrationPhase.done;
      _outcome = outcome;
      if (offset != null) _savedOffsetSeconds = offset;
    });
  }

  Future<void> _save(double? offsetSeconds) async {
    try {
      await widget.store.save(offsetSeconds);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the calibration: $e');
    }
  }

  void _cancel() {
    _progress.stop();
    _stopListening();
    unawaited(_player.stop().catchError((Object e) {
      debugPrint('Calibration beat failed to stop: $e');
    }));
    setState(() => _phase = _CalibrationPhase.idle);
  }

  void _clear() {
    unawaited(_save(null));
    setState(() {
      _savedOffsetSeconds = null;
      _outcome = null;
      _phase = _CalibrationPhase.idle;
    });
  }

  void _stopListening() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _audioFallbackTimer?.cancel();
    _audioFallbackTimer = null;
    _tailTimer?.cancel();
    _tailTimer = null;
    _micSubscription?.cancel();
    _micSubscription = null;
    final mic = _mic;
    if (mic != null) _releaseMic(mic);
    _mic = null;
  }

  void _releaseMic(MicInput mic) {
    unawaited(mic.stop().catchError((Object e) {
      debugPrint('Calibration microphone failed to stop: $e');
    }));
  }

  static String _ms(double seconds) => '${(seconds * 1000).round()} ms';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final saved = _savedOffsetSeconds;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'A tambourine beat plays for about 10 seconds. Listen to the first '
              '$_settleBeats beats, then play along on your instrument, one hit on '
              'every beat, until it stops.\n\n'
              'Listen the way you practise: if you practise with headphones, wear '
              'them now.',
            ),
            const SizedBox(height: 16),
            Text(
              saved == null ? 'Not calibrated yet.' : 'Saved offset: ${_ms(saved)}',
              key: const Key('calibration_saved_offset'),
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_phase == _CalibrationPhase.running) ...[
              AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => LinearProgressIndicator(value: _progress.value),
              ),
              const SizedBox(height: 8),
              Text('Hits heard: ${_hitTimes.length}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('calibration_stop_button'),
                onPressed: _cancel,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ] else ...[
              ElevatedButton.icon(
                key: const Key('calibration_start_button'),
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(_phase == _CalibrationPhase.done ? 'Calibrate again' : 'Start'),
              ),
              if (saved != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('calibration_clear_button'),
                  onPressed: _clear,
                  child: const Text('Clear saved offset'),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_outcome != null && _phase == _CalibrationPhase.done) ...[
              const SizedBox(height: 24),
              _buildOutcome(context, _outcome!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOutcome(BuildContext context, CalibrationOutcome outcome) {
    final textTheme = Theme.of(context).textTheme;
    final offset = outcome.offsetSeconds;
    if (offset != null) {
      return Column(
        key: const Key('calibration_result'),
        children: [
          Text('Offset: ${_ms(offset)}', style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Averaged over ${outcome.hitCount} hits, steady to within '
            '±${_ms(outcome.spreadSeconds)}. Saved.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final String message;
    switch (outcome.failure!) {
      case CalibrationFailure.tooFewHits:
        message = 'Only ${outcome.hitCount} hits were heard after the first '
            '$_settleBeats beats; at least ${TapCalibration.minHits} are needed. '
            'Nothing was saved.';
      case CalibrationFailure.unsteady:
        message = 'The hits were too uneven against the beat to average. '
            'Nothing was saved.';
    }
    return Text(
      message,
      key: const Key('calibration_result'),
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
