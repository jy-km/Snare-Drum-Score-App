import 'dart:typed_data';

import 'hit_judge.dart';
import 'onset_detector.dart';

enum LiveJudgeState {
  /// Waiting to hear the count-in clicks; nothing can be judged yet.
  listeningForCountIn,

  /// Hits are being placed on the timeline and judged -- because the
  /// count-in was heard, or failing that by a trusted estimate (see
  /// [LiveJudge.timingIsEstimated]).
  judging,

  /// The count-in should have been over by now and was never heard (e.g.
  /// the sound went to headphones), and there was no estimate good enough
  /// to judge by instead. Nothing will be judged.
  countInNotHeard,
}

/// Judges a practice run from live microphone audio.
///
/// The microphone's clock and the practice timeline's clock have no known
/// relation: the mic starts at some arbitrary moment, and the phone takes an
/// unknown time to turn "play this" into sound. So instead of guessing those
/// delays, this listens for the count-in clicks, which the phone plays out
/// loud at known timeline times. Hearing them in the recording pins the
/// timeline to the recording exactly, as the sound actually reached the mic
/// -- and since the player keeps time with those same clicks, a hit's
/// distance from its note on that timeline is how early or late it really
/// was.
class LiveJudge {
  final StreamingOnsetDetector _detector;
  final List<double> _clickTimes;
  final double _judgingStartsAt;
  final HitJudge _judge;

  final _onsetTimes = <double>[];
  int _nextOnsetToJudge = 0;

  /// Recording time minus timeline time, once the count-in has been heard.
  double? _timelineOffset;
  LiveJudgeState _state = LiveJudgeState.listeningForCountIn;

  /// [clickTimes] and [noteTimes] are timeline seconds, ascending; the
  /// clicks are the count-in. Hits earlier than [judgingStartsAt] on the
  /// timeline are ignored rather than matched to notes -- they are the
  /// count-in clicks themselves, or the player tapping along with them.
  LiveJudge({
    required int sampleRate,
    required List<double> clickTimes,
    required List<double> noteTimes,
    List<(double, double)> rests = const [],
    required this._judgingStartsAt,
  })  : assert(clickTimes.isNotEmpty),
        _detector = StreamingOnsetDetector(sampleRate: sampleRate),
        _clickTimes = clickTimes,
        _judge = HitJudge(noteTimes, rests: rests);

  LiveJudgeState get state => _state;

  /// See [HitJudge.counts].
  Map<Judgement, int> get counts => _judge.counts;

  /// A detected click may sit this far from where the others say it should
  /// be and still count as that click.
  static const double _clickToleranceSeconds = 0.03;

  /// How far the count-in may be found from where [expectTimelineStart] said
  /// it would be. Wide enough for the delays that estimate can't see (the
  /// phone's speaker and microphone latency), narrow enough that the
  /// player's own playing a measure later is never taken for the count-in.
  static const double _startSlackSeconds = 0.5;

  /// How long after the last click should have been heard to keep listening
  /// for it before giving up.
  static const double _giveUpAfterSeconds = 1;

  /// Roughly where timeline zero falls in the recording, once known.
  double? _expectedOffset;
  bool _expectedOffsetIsTrusted = false;
  bool _timingIsEstimated = false;

  /// Tells the judge roughly where in the recording the timeline starts
  /// ([recordingSeconds] from the start of the audio fed in). May be called
  /// again as the estimate improves, until the count-in has been found or
  /// given up on. Nothing is judged until this has been called.
  ///
  /// The count-in clicks themselves give the exact answer; the estimate is
  /// there so that evenly spaced playing later in the run can't pass for
  /// the count-in when the real one was never heard.
  ///
  /// With [trusted], the estimate is good enough to judge by on its own:
  /// if the count-in is never heard, the run is judged against the estimate
  /// ([timingIsEstimated]) instead of not at all.
  void expectTimelineStart(double recordingSeconds, {bool trusted = false}) {
    if (_state != LiveJudgeState.listeningForCountIn) return;
    _expectedOffset = recordingSeconds;
    _expectedOffsetIsTrusted = trusted;
  }

  /// Whether hits are being placed on the timeline by estimate rather than
  /// by the count-in having been heard.
  bool get timingIsEstimated => _timingIsEstimated;

  /// Where in the recording the timeline starts, as hits are being placed
  /// by -- heard or estimated -- or null while nothing is being judged.
  double? get timelineStart => _state == LiveJudgeState.judging ? _timelineOffset : null;

  /// Where in the recording the timeline starts, as pinned down by hearing
  /// the count-in -- null if it hasn't been heard (yet, or at all).
  double? get heardTimelineStart => _timingIsEstimated ? null : _timelineOffset;

  /// Feeds in the next stretch of microphone audio and returns whatever it
  /// settled: hits judged against their notes, and notes that have now gone
  /// by without a hit.
  List<JudgedHit> addSamples(Int16List samples) {
    for (final onset in _detector.addSamples(samples)) {
      _onsetTimes.add(onset.timeSeconds);
    }

    final expectedOffset = _expectedOffset;
    if (_state == LiveJudgeState.listeningForCountIn && expectedOffset != null) {
      _timelineOffset = alignCountIn(
        _onsetTimes,
        _clickTimes,
        _clickToleranceSeconds,
        expectedOffset: expectedOffset,
        offsetSlack: _startSlackSeconds,
      );
      if (_timelineOffset != null) {
        _state = LiveJudgeState.judging;
      } else if (_detector.secondsReceived >
          expectedOffset + _clickTimes.last + _startSlackSeconds + _giveUpAfterSeconds) {
        if (_expectedOffsetIsTrusted) {
          _timelineOffset = expectedOffset;
          _timingIsEstimated = true;
          _state = LiveJudgeState.judging;
        } else {
          _state = LiveJudgeState.countInNotHeard;
        }
      }
    }
    if (_state != LiveJudgeState.judging) return const [];

    final offset = _timelineOffset!;
    final judged = <JudgedHit>[];
    for (; _nextOnsetToJudge < _onsetTimes.length; _nextOnsetToJudge++) {
      final hitTime = _onsetTimes[_nextOnsetToJudge] - offset;
      if (hitTime < _judgingStartsAt - Judgement.good.windowSeconds) continue;
      // Settle the notes this hit came too late for first, so events come
      // out in the order they happened.
      judged.addAll(_judge.advanceTo(hitTime));
      final hit = _judge.addHit(hitTime);
      if (hit != null) judged.add(hit);
    }
    // Any hit before this moment has already been reported by the detector,
    // so a note whose window closed before it really was not hit.
    judged.addAll(
      _judge.advanceTo(_detector.secondsReceived - _detector.latencySeconds - offset),
    );
    return judged;
  }

  /// Ends the run: every note still waiting for a hit becomes a miss.
  List<JudgedHit> finish() => _state == LiveJudgeState.judging ? _judge.finish() : const [];

  /// Finds where the count-in sits in a recording: returns the recording
  /// time of timeline time zero, or null if the clicks can't be found.
  ///
  /// [onsetTimes] are the hits detected so far (recording seconds),
  /// [clickTimes] when each click plays (timeline seconds). Every click must
  /// be found, at the spacing the timeline says, within [tolerance] -- a
  /// pattern stray sounds are very unlikely to form by chance, as long as
  /// there is more than one click. With [expectedOffset], only answers
  /// within [offsetSlack] of it are considered.
  static double? alignCountIn(
    List<double> onsetTimes,
    List<double> clickTimes,
    double tolerance, {
    double? expectedOffset,
    double offsetSlack = 0,
  }) {
    for (final anchor in onsetTimes) {
      final offset = anchor - clickTimes.first;
      if (expectedOffset != null && (offset - expectedOffset).abs() > offsetSlack) continue;
      var residualSum = 0.0;
      var allFound = true;
      for (final click in clickTimes) {
        final residual = _nearestResidual(onsetTimes, click + offset);
        if (residual == null || residual.abs() > tolerance) {
          allFound = false;
          break;
        }
        residualSum += residual;
      }
      // Centre the offset on all the clicks, not just the anchor one.
      if (allFound) return offset + residualSum / clickTimes.length;
    }
    return null;
  }

  /// Signed distance from [time] to the nearest of [onsetTimes], or null if
  /// there are none.
  static double? _nearestResidual(List<double> onsetTimes, double time) {
    double? best;
    for (final onset in onsetTimes) {
      final residual = onset - time;
      if (best == null || residual.abs() < best.abs()) best = residual;
    }
    return best;
  }
}
