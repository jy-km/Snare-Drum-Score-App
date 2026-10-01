import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/scheduler.dart';

import '../models/rhythm_score.dart';
import 'click_sound.dart';

/// Plays a [RhythmScore] at a given tempo by rendering the whole sequence to
/// a single linear audio buffer up front (mixing each event's click waveform
/// in at its exact sample position, like bouncing a MIDI track to audio) and
/// playing that buffer once.
///
/// An earlier version retriggered two long-lived players live via
/// seek()+resume() per hit. That was unreliable: audioplayers' seek()/resume()
/// are async platform-channel round-trips that don't complete fast or
/// deterministically enough relative to typical tempos, which caused
/// spurious extra retriggers when two calls overlapped, and made repeat
/// playthroughs of the same pattern sound different. Rendering once and
/// playing back linearly has no retrigger window, so it's deterministic by
/// construction.
///
/// [positionStream] reports a continuous fractional "unit position" (e.g.
/// `4.5` = halfway through the 5th `RhythmGrid` unit), driven by a local
/// per-frame clock rather than per-frame native position queries: the audio
/// player's own reported position is used only to calibrate that local clock
/// once playback truly starts, and to gently correct drift thereafter — not
/// as the direct source of each frame's displayed position. This avoids
/// jitter/latency from repeated platform-channel round-trips and gives a
/// smoothly moving value suitable for a continuously-moving playhead, rather
/// than discrete per-note jumps.
class RhythmPlayer {
  final _player = AudioPlayer(playerId: 'rhythm_player');
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  bool _isPlaying = false;

  double _msPerUnit = 0;
  int _totalUnits = 0;
  DateTime? _anchor;
  Duration? _lastAcceptedPosition;

  /// Native position reports below this, right after play() starts, are
  /// treated as "still buffering," not real progress -- confirmed via
  /// on-device logging that the native player reports position=0 for
  /// roughly the first ~400ms before real position data arrives. Anchoring
  /// on one of those zero readings makes the local clock creep out ahead of
  /// real playback (each stale zero looks like "we're still at the start,
  /// right now"), which then needs a visible correction jump once real data
  /// finally arrives.
  static const _minStartupPosition = Duration(milliseconds: 20);

  final _positionController = StreamController<double?>.broadcast();

  bool get isPlaying => _isPlaying;

  /// Continuous elapsed position in `RhythmGrid` units, or null when
  /// stopped.
  Stream<double?> get positionStream => _positionController.stream;

  Future<void> play(RhythmScore score, {int? tempoBpmOverride}) async {
    await stop();

    final tempoBpm = tempoBpmOverride ?? score.tempoBpm;
    _msPerUnit = 60000 / tempoBpm / RhythmGrid.unitsPerQuarterNote;
    _totalUnits = score.measures.length * score.unitsPerMeasure;
    final normalSamples = await ClickSound.normalSamples(score.instrument);
    final accentSamples = await ClickSound.accentSamples(score.instrument);
    final wavBytes = _renderSequence(
      score,
      msPerUnit: _msPerUnit,
      normalSamples: normalSamples,
      accentSamples: accentSamples,
    );

    _isPlaying = true;
    _anchor = null;
    _lastAcceptedPosition = null;

    _positionSubscription = _player.onPositionChanged.listen(_onPositionSample);
    _completeSubscription = _player.onPlayerComplete.listen((_) => _stopInternal());

    await _player.play(BytesSource(wavBytes));
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _onPositionSample(Duration position) {
    // We never seek during playback, so position should only move forward.
    // On-device logging also caught the native player briefly reporting a
    // position *earlier* than the previous one (a real regression in the
    // reported value, not just noise) about a second into playback, before
    // it stabilized. Reject anything that goes backward rather than
    // correcting toward it.
    if (_lastAcceptedPosition != null && position < _lastAcceptedPosition!) {
      return;
    }
    _lastAcceptedPosition = position;

    if (_anchor == null) {
      if (position < _minStartupPosition) return;
      _anchor = DateTime.now().subtract(position);
      return;
    }

    // Gentle correction thereafter, to avoid visible jumps from any single
    // noisy sample while still preventing long-term drift.
    final sampleAnchor = DateTime.now().subtract(position);
    final driftMicros = sampleAnchor.difference(_anchor!).inMicroseconds;
    _anchor = _anchor!.add(Duration(microseconds: (driftMicros * 0.2).round()));
  }

  void _onFrame(Duration _) {
    if (!_isPlaying) return;
    final anchor = _anchor;
    if (anchor != null) {
      final elapsedMs = DateTime.now().difference(anchor).inMicroseconds / 1000.0;
      final unitPosition = (elapsedMs / _msPerUnit).clamp(0, _totalUnits.toDouble()).toDouble();
      _positionController.add(unitPosition);
    }
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  /// Mixes each event's click samples into a silent buffer at its exact
  /// sample position, producing one continuous WAV covering the whole score.
  Uint8List _renderSequence(
    RhythmScore score, {
    required double msPerUnit,
    required Int16List normalSamples,
    required Int16List accentSamples,
  }) {
    // Kept fractional and rounded per hit, not once per unit: a unit is a
    // small fraction of a beat, so a per-unit rounding error would add up
    // across the whole score and drift the audio away from the playhead.
    final samplesPerUnit = ClickSound.sampleRate * msPerUnit / 1000;
    final totalUnits = score.measures.length * score.unitsPerMeasure;
    final tailLength = normalSamples.length > accentSamples.length
        ? normalSamples.length
        : accentSamples.length;
    final mixBuffer = Int32List((totalUnits * samplesPerUnit).ceil() + tailLength);

    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++) {
      final measure = score.measures[measureIndex];
      var unitCursor = measureIndex * score.unitsPerMeasure;

      for (final event in measure.events) {
        if (!event.isRest) {
          final startSample = (unitCursor * samplesPerUnit).round();
          final clickSamples = event.type == EventType.accent ? accentSamples : normalSamples;
          for (var i = 0; i < clickSamples.length; i++) {
            mixBuffer[startSample + i] += clickSamples[i];
          }
        }
        unitCursor += event.durationUnits;
      }
    }

    final finalSamples = Int16List(mixBuffer.length);
    for (var i = 0; i < mixBuffer.length; i++) {
      finalSamples[i] = mixBuffer[i].clamp(-32768, 32767);
    }
    return ClickSound.pcm16ToWav(finalSamples);
  }

  Future<void> stop() async {
    await _player.stop();
    _stopInternal();
  }

  void _stopInternal() {
    _isPlaying = false;
    _anchor = null;
    _lastAcceptedPosition = null;
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _positionController.add(null);
  }

  Future<void> dispose() async {
    _stopInternal();
    await _player.dispose();
    await _positionController.close();
  }
}
