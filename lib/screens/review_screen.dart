import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../services/click_sound.dart';
import '../services/hit_judge.dart';
import '../services/run_review.dart';
import '../widgets/judgement_style.dart';
import '../widgets/staff_notation_view.dart';

/// Goes back over a judged practice run: every measure with each hit marked
/// where it landed (and labelled with how far off it was), the notes that
/// were most off, and a replay of what the microphone heard with a playhead
/// moving across the score in step with it.
class ReviewScreen extends StatefulWidget {
  final RunReview review;

  const ReviewScreen({super.key, required this.review});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> with SingleTickerProviderStateMixin {
  /// See `PracticeScreen`'s identically named constants: the replay's audio
  /// reports position 0 while it is still starting up, and if it never
  /// reports a position at all (no audio, as in tests) the playhead goes
  /// ahead on the clock alone.
  static const _minStartupPosition = Duration(milliseconds: 20);
  static const _audioFallbackDelay = Duration(milliseconds: 1000);

  final _player = AudioPlayer(playerId: 'review_replay');
  late final AnimationController _replay;
  late final Map<int, List<StaffMark>> _marks = _buildMarks();
  late final List<GlobalKey> _measureKeys =
      List.generate(widget.review.layout.measureCount, (_) => GlobalKey());

  StreamSubscription<Duration>? _positionSubscription;
  Timer? _audioFallbackTimer;
  bool _replaying = false;
  bool _started = false;

  /// The timeline measure the playhead is in, while replaying.
  int? _replayMeasure;

  RunReview get _review => widget.review;

  @override
  void initState() {
    super.initState();
    _replay = AnimationController(
      vsync: this,
      duration: Duration(microseconds: (_review.audioSeconds * 1e6).round()),
    )
      ..addListener(_onReplayTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _stopReplay();
      });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _audioFallbackTimer?.cancel();
    _replay.dispose();
    _player.dispose();
    super.dispose();
  }

  Map<int, List<StaffMark>> _buildMarks() {
    final marks = <int, List<StaffMark>>{};
    for (final hit in _review.judgements) {
      final (measureIndex, mark) = judgementMark(
        hit,
        layout: _review.layout,
        noteTimes: _review.noteTimes,
        secondsPerUnit: _review.secondsPerUnit,
        withOffset: true,
      );
      (marks[measureIndex] ??= []).add(mark);
    }
    return marks;
  }

  double get _replayUnits =>
      _replay.value * _review.audioSeconds / _review.secondsPerUnit;

  void _startReplay() {
    _started = false;
    setState(() => _replaying = true);
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (_started || position < _minStartupPosition) return;
      _beginPlayhead(clock.now().subtract(position));
    });
    _audioFallbackTimer = Timer(_audioFallbackDelay, () {
      if (!_started) _beginPlayhead(clock.now());
    });
    unawaited(_playAudio());
  }

  Future<void> _playAudio() async {
    try {
      final wav = ClickSound.pcm16ToWav(_review.audio, rate: _review.sampleRate);
      await _player.play(BytesSource(wav));
    } catch (e) {
      debugPrint('Review replay audio failed to play: $e');
    }
  }

  /// Starts the playhead from [anchor], the wall-clock moment the replay's
  /// audio was at its start -- the same single-clock approach as practice.
  void _beginPlayhead(DateTime anchor) {
    _started = true;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _audioFallbackTimer?.cancel();
    _audioFallbackTimer = null;
    final elapsed = clock.now().difference(anchor);
    _replay.forward(
      from: (elapsed.inMicroseconds / _replay.duration!.inMicroseconds).clamp(0.0, 1.0),
    );
  }

  void _onReplayTick() {
    final measure = _review.layout.indexAt(_replayUnits);
    if (measure != _replayMeasure) {
      _replayMeasure = measure;
      _scrollTo(measure);
    }
    setState(() {});
  }

  void _stopReplay() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _audioFallbackTimer?.cancel();
    _audioFallbackTimer = null;
    if (_replay.isAnimating) _replay.stop();
    unawaited(_player.stop().catchError((Object e) {
      debugPrint('Review replay audio failed to stop: $e');
    }));
    setState(() {
      _replaying = false;
      _replayMeasure = null;
    });
  }

  void _scrollTo(int timelineMeasure) {
    final context = _measureKeys[timelineMeasure].currentContext;
    if (context == null) return;
    unawaited(Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      alignment: 0.3,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final layout = _review.layout;
    final mostOff = _review.mostOff();
    final missed = _review.missedNotes;

    return Scaffold(
      appBar: AppBar(title: Text('Review: ${layout.score.title}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Judgement.values
                      .map((j) => '${judgementLabel(j)} ${_review.counts[j]}')
                      .join('  ·  '),
                  key: const Key('review_tally'),
                  style: textTheme.titleMedium,
                ),
              ),
              if (_review.timingEstimated)
                Text(
                  'The count-in wasn\'t heard on this run, so its timing was estimated.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Text('Most off', style: textTheme.titleSmall),
              if (mostOff.isEmpty)
                const Text('Nothing: every note you hit was Perfect.')
              else
                for (final hit in mostOff)
                  _ReviewLine(
                    key: Key('review_most_off_${hit.noteIndex}'),
                    text: '${_review.locate(hit)}: ${judgementLabelWithDirection(hit)}, '
                        '${offsetText(hit.offsetSeconds!)} '
                        '(${hit.offsetSeconds! < 0 ? 'early' : 'late'})',
                    color: judgementColor(hit.judgement),
                    onTap: () => _scrollTo(_review.timelineMeasureOf(hit)),
                  ),
              if (missed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Missed', style: textTheme.titleSmall),
                Text(
                  missed.map(_review.locate).join('; '),
                  key: const Key('review_missed'),
                  style: TextStyle(color: judgementColor(Judgement.miss)),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  key: Key(_replaying ? 'review_stop_button' : 'review_play_button'),
                  onPressed: _replaying ? _stopReplay : _startReplay,
                  icon: Icon(_replaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_replaying ? 'Stop' : 'Replay'),
                ),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < layout.measureCount; index++)
                Padding(
                  key: _measureKeys[index],
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(layout.labelFor(index), style: textTheme.bodySmall),
                      StaffNotationView(
                        key: Key('review_measure_$index'),
                        measure: layout.measureAt(index),
                        showTimeSignature: layout.showsTimeSignature(index),
                        playheadUnits: _replayMeasure == index
                            ? _replayUnits - layout.starts[index]
                            : null,
                        marks: _marks[index] ?? const [],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable line of the "Most off" list.
class _ReviewLine extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _ReviewLine({super.key, required this.text, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
