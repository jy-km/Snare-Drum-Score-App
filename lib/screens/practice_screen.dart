import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/click_sound.dart';
import '../services/practice_slot_assignment.dart';
import '../widgets/staff_notation_view.dart';

enum _PracticePhase { idle, running, done }

/// A silent-playback practice mode: the device shows the player where they
/// are in the score (via a moving playhead across 3 fixed, rotating measure
/// slots) but does not play the rhythm's sound -- the player plays it
/// themselves on their instrument. Only a lead-in "Count-in" measure (4
/// audible quarter-note clicks) before Measure 1 is audible.
///
/// The count-in is just another measure prepended to the same timeline the
/// real measures play on, driven by the same single [AnimationController] --
/// not a separate Timer racing a separate audio system. That means the
/// transition from the last count-in click into Measure 1 is exactly the
/// same kind of continuous playhead motion as the transition between any two
/// real measures, so there's nothing to keep in sync. The controller's start
/// is calibrated once against the count-in click's actual audio position
/// (the same technique `RhythmPlayer` uses), since audio playback has
/// several hundred ms of startup latency after `play()` is called -- without
/// that calibration, the last click-to-Measure-1 gap comes up short by
/// however much that latency was.
class PracticeScreen extends StatefulWidget {
  final RhythmScore score;

  const PracticeScreen({super.key, required this.score});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  static const _minTempoBpm = 20;
  static const _maxTempoBpm = 300;
  static const _tempoStepBpm = 5;
  static const _countInBeats = 4;
  static const _timelineMeasureCount = RhythmGrid.measuresCount + 1;
  static const _totalUnits = _timelineMeasureCount * RhythmGrid.unitsPerMeasure;

  /// Native position reports below this, right after play() starts, mean
  /// "still buffering," not real progress -- see `RhythmPlayer`'s identical
  /// constant and doc comment for how this was measured on-device.
  static const _minCountInStartupPosition = Duration(milliseconds: 20);

  /// If no real audio position sample arrives within this long (e.g. no
  /// audio platform channel at all, as in widget tests), proceed anyway
  /// rather than hang forever -- this is well above the ~400ms startup
  /// latency `RhythmPlayer` measured on real hardware, so it should only
  /// ever fire when audio genuinely isn't available.
  static const _countInFallbackDelay = Duration(milliseconds: 1000);

  static final _countdownMeasure = Measure(
    List.generate(_countInBeats, (_) => const RhythmEvent(NoteValue.quarter, EventType.normal)),
  );

  final _slots = PracticeSlotAssignment(measuresCount: _timelineMeasureCount);
  final _clickPlayer = AudioPlayer(playerId: 'practice_click');
  late final AnimationController _playbackController;

  StreamSubscription<Duration>? _countInPositionSubscription;
  Timer? _countInFallbackTimer;
  DateTime? _countInAnchor;
  _PracticePhase _phase = _PracticePhase.idle;
  late int _practiceTempoBpm;
  double _globalUnits = 0;

  @override
  void initState() {
    super.initState();
    _practiceTempoBpm = widget.score.tempoBpm;
    _playbackController = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_onPlaybackTick)
      ..addStatusListener(_onPlaybackStatus);
  }

  @override
  void dispose() {
    _countInPositionSubscription?.cancel();
    _countInFallbackTimer?.cancel();
    _playbackController.dispose();
    _clickPlayer.dispose();
    super.dispose();
  }

  double get _msPerUnit => 60000 / _practiceTempoBpm / RhythmGrid.subdivisionsPerBeat;

  String _labelFor(int timelineIndex) => timelineIndex == 0 ? 'Count-in' : 'Measure $timelineIndex';

  Measure _measureFor(int timelineIndex) =>
      timelineIndex == 0 ? _countdownMeasure : widget.score.measures[timelineIndex - 1];

  void _onPlaybackTick() {
    final units = _playbackController.value * _totalUnits;
    final measureIndex =
        (units / RhythmGrid.unitsPerMeasure).floor().clamp(0, _timelineMeasureCount - 1);
    if (_slots.currentMeasureIndex != measureIndex) {
      _slots.advanceTo(measureIndex);
    }
    setState(() => _globalUnits = units);
  }

  void _onPlaybackStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() => _phase = _PracticePhase.done);
    }
  }

  /// Renders the count-in's 4 clicks into a single buffer up front and plays
  /// it with one `play()` call -- triggering `play()` on the same player
  /// once per beat sounded uneven or dropped the first beat, since each call
  /// is an async platform-channel round-trip and back-to-back calls on the
  /// same player race each other (the same retrigger bug `RhythmPlayer` hit
  /// and fixed the same way).
  Uint8List _renderCountIn() {
    final beatMs = 60000 / _practiceTempoBpm;
    final samplesPerBeat = (ClickSound.sampleRate * beatMs / 1000).round();
    final tailLength = ClickSound.normalClickSamples.length;
    final mixBuffer = Int32List(samplesPerBeat * _countInBeats + tailLength);

    for (var beat = 0; beat < _countInBeats; beat++) {
      final startSample = beat * samplesPerBeat;
      for (var i = 0; i < ClickSound.normalClickSamples.length; i++) {
        mixBuffer[startSample + i] += ClickSound.normalClickSamples[i];
      }
    }

    final finalSamples = Int16List(mixBuffer.length);
    for (var i = 0; i < mixBuffer.length; i++) {
      finalSamples[i] = mixBuffer[i].clamp(-32768, 32767);
    }
    return ClickSound.pcm16ToWav(finalSamples);
  }

  void _start() {
    _slots.reset();
    setState(() => _phase = _PracticePhase.running);
    _countInAnchor = null;
    _countInPositionSubscription = _clickPlayer.onPositionChanged.listen(_onCountInPositionSample);
    unawaited(_clickPlayer.play(BytesSource(_renderCountIn())).catchError((_) {}));
    _countInFallbackTimer = Timer(_countInFallbackDelay, () {
      if (_countInAnchor == null) _beginTimeline(DateTime.now());
    });
  }

  void _onCountInPositionSample(Duration position) {
    if (_countInAnchor != null || position < _minCountInStartupPosition) return;
    _beginTimeline(DateTime.now().subtract(position));
  }

  /// Starts the single timeline-wide clock anchored at [anchor] -- the
  /// real wall-clock moment the count-in's audio position was actually zero.
  /// Seeding the controller's starting value with how much time has already
  /// passed since then (rather than starting fresh at value 0 "now") is what
  /// keeps the playhead's motion correctly aligned with the audio that's
  /// already playing, instead of running late by however long calibration
  /// itself took to arrive.
  void _beginTimeline(DateTime anchor) {
    _countInAnchor = anchor;
    _countInPositionSubscription?.cancel();
    _countInPositionSubscription = null;
    _countInFallbackTimer?.cancel();
    _countInFallbackTimer = null;

    _playbackController.duration = Duration(milliseconds: (_totalUnits * _msPerUnit).round());
    final elapsedSinceAnchor = DateTime.now().difference(anchor);
    final startFraction = (elapsedSinceAnchor.inMicroseconds /
            _playbackController.duration!.inMicroseconds)
        .clamp(0.0, 1.0);
    _playbackController.forward(from: startFraction);
  }

  void _returnToIdle() {
    _countInPositionSubscription?.cancel();
    _countInPositionSubscription = null;
    _countInFallbackTimer?.cancel();
    _countInFallbackTimer = null;
    _countInAnchor = null;
    if (_playbackController.isAnimating) _playbackController.stop();
    setState(() {
      _phase = _PracticePhase.idle;
      _slots.reset();
      _globalUnits = 0;
    });
  }

  void _adjustTempo(int delta) {
    setState(() {
      _practiceTempoBpm = (_practiceTempoBpm + delta).clamp(_minTempoBpm, _maxTempoBpm);
    });
  }

  String get _statusText {
    switch (_phase) {
      case _PracticePhase.idle:
        return 'Ready';
      case _PracticePhase.running:
        return (_slots.currentMeasureIndex ?? 0) == 0 ? 'Get ready...' : 'Playing';
      case _PracticePhase.done:
        return 'Done';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Practice: ${widget.score.title}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _statusText,
                key: const Key('practice_status_text'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _TempoStepper(
                bpm: _practiceTempoBpm,
                enabled: _phase == _PracticePhase.idle,
                onDecrease: () => _adjustTempo(-_tempoStepBpm),
                onIncrease: () => _adjustTempo(_tempoStepBpm),
              ),
              const SizedBox(height: 16),
              // Stacked full-width, one measure per row (like systems in sheet
              // music) rather than side-by-side: splitting the screen width 3
              // ways left too little room between notes to read.
              Column(
                children: PracticeSlot.values.map((slot) {
                  final timelineIndex = _slots.content[slot];
                  final isActive =
                      timelineIndex != null && timelineIndex == _slots.currentMeasureIndex;
                  final playheadUnits = isActive
                      ? _globalUnits - timelineIndex * RhythmGrid.unitsPerMeasure
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PracticeSlotView(
                      key: Key('practice_slot_${slot.name}'),
                      label: timelineIndex == null ? '' : _labelFor(timelineIndex),
                      measureIndex: timelineIndex,
                      measure: timelineIndex != null ? _measureFor(timelineIndex) : null,
                      isActive: isActive,
                      playheadUnits: playheadUnits,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _buildActionButton(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_phase) {
      case _PracticePhase.idle:
        return ElevatedButton.icon(
          key: const Key('practice_start_button'),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        );
      case _PracticePhase.running:
        return ElevatedButton.icon(
          key: const Key('practice_stop_button'),
          onPressed: _returnToIdle,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        );
      case _PracticePhase.done:
        return ElevatedButton.icon(
          key: const Key('practice_again_button'),
          onPressed: _returnToIdle,
          icon: const Icon(Icons.replay),
          label: const Text('Practice Again'),
        );
    }
  }
}

class _TempoStepper extends StatelessWidget {
  final int bpm;
  final bool enabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _TempoStepper({
    required this.bpm,
    required this.enabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('practice_tempo_decrease'),
          onPressed: enabled ? onDecrease : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 100,
          child: Text(
            '$bpm BPM',
            key: const Key('practice_tempo_value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const Key('practice_tempo_increase'),
          onPressed: enabled ? onIncrease : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _PracticeSlotView extends StatelessWidget {
  final String label;
  final int? measureIndex;
  final Measure? measure;
  final bool isActive;
  final double? playheadUnits;

  const _PracticeSlotView({
    super.key,
    required this.label,
    required this.measureIndex,
    required this.measure,
    required this.isActive,
    required this.playheadUnits,
  });

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? highlightColor : Colors.transparent,
            width: 2,
          ),
          color: isActive ? highlightColor.withValues(alpha: 0.08) : null,
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: measureIndex == null
                  ? const SizedBox(key: ValueKey('blank'), height: 140)
                  : StaffNotationView(
                      key: ValueKey(measureIndex),
                      measure: measure!,
                      playheadUnits: playheadUnits,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
