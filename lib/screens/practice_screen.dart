import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/click_sound.dart';
import '../services/dynamics_check.dart';
import '../services/hit_judge.dart';
import '../services/live_judge.dart';
import '../services/mic_input.dart';
import '../services/mic_latency.dart';
import '../services/practice_history.dart';
import '../services/practice_slot_assignment.dart';
import '../services/run_review.dart';
import '../services/screen_awake.dart';
import '../services/timeline_layout.dart';
import '../services/track_sections.dart';
import '../widgets/app_theme.dart';
import '../widgets/confetti.dart';
import '../widgets/dynamics_results.dart';
import '../widgets/judgement_style.dart';
import '../widgets/mic_light.dart';
import '../widgets/note_dialog.dart';
import '../widgets/settings_scope.dart';
import '../widgets/staff_notation_view.dart';
import '../widgets/tap_tempo_button.dart';
import '../widgets/tempo_mark.dart';
import '../widgets/timing_needle.dart';
import 'review_screen.dart';

enum _PracticePhase { idle, running, done }

/// A practice mode showing the player where they are in the score (via a
/// moving playhead across 3 fixed, rotating measure slots). A lead-in
/// "Count-in" measure is always audible; whether the 8 real measures are
/// *also* audible (playing the rhythm's actual hit sounds, so the player can
/// follow along) or silent (so the player performs the rhythm themselves,
/// unassisted) is a per-session toggle -- see [_rhythmSoundEnabled].
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

  /// Makes the microphone a run listens through to judge the player's hits.
  /// Replaceable so tests can feed in canned audio.
  final MicInput Function() createMicInput;

  /// Where this phone's measured sound delay is remembered between runs.
  final MicLatencyStore latencyStore;

  /// Where the sound delay the player measured in calibration mode is kept.
  final MicCalibrationStore calibrationStore;

  /// The track (score file) being practised: each judged run is saved to
  /// its practice history. Null (e.g. in tests) saves nothing.
  final String? scoreId;

  /// Where runs are saved; by default the app's files.
  final PracticeHistoryStore? historyStore;

  /// Set when [score] is a section of the track [scoreId] rather than the
  /// whole of it: measures are numbered as in the track, and runs are saved
  /// to the track's history marked with the section.
  final TrackSection? section;

  /// Keeps the screen on while the practice screen is open.
  final ScreenAwake screenAwake;

  const PracticeScreen({
    super.key,
    required this.score,
    this.createMicInput = DeviceMicInput.new,
    this.latencyStore = const FileMicLatencyStore(),
    this.calibrationStore = const FileMicCalibrationStore(),
    this.scoreId,
    this.historyStore,
    this.section,
    this.screenAwake = const DeviceScreenAwake(),
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> with SingleTickerProviderStateMixin {
  static const _minTempoBpm = 20;
  static const _maxTempoBpm = 300;
  static const _tempoStepBpm = 5;

  /// A run at least this accurate ([runAccuracy]) suggests going faster.
  static const _readyForFasterAccuracy = 0.85;

  /// How the count-in and the score's measures sit on one timeline -- the
  /// same layout the review screen replays a run on.
  late final _layout = TimelineLayout(
    widget.score,
    firstMeasureNumber: (widget.section?.firstMeasure ?? 0) + 1,
  );

  int get _timelineMeasureCount => _layout.measureCount;
  TimeSignature get _countInMeter => _layout.countInMeter;
  int get _countInBeats => _countInMeter.beats;

  /// Units occupied by one count-in beat -- a quarter note's worth for a
  /// quarter-note beat unit, a half note's worth for a half-note beat unit.
  /// The click spacing must match this, not a hardcoded quarter note, or the
  /// count-in would end up shorter than a measure whenever the beat unit
  /// isn't 4.
  int get _unitsPerBeat => _countInMeter.unitsPerBeat;
  List<int> get _timelineStarts => _layout.starts;
  int get _totalUnits => _layout.totalUnits;
  int _timelineIndexAt(double units) => _layout.indexAt(units);
  bool _showsTimeSignature(int index) => _layout.showsTimeSignature(index);

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

  late final _slots = PracticeSlotAssignment(measuresCount: _timelineMeasureCount);
  final _clickPlayer = AudioPlayer(playerId: 'practice_click');
  late final AnimationController _playbackController;

  StreamSubscription<Duration>? _countInPositionSubscription;
  Timer? _countInFallbackTimer;
  DateTime? _countInAnchor;
  _PracticePhase _phase = _PracticePhase.idle;
  late int _practiceTempoBpm;
  double _globalUnits = 0;
  bool _rhythmSoundEnabled = false;

  /// The microphone and judge for the current run, when it is being judged.
  /// A run is judged only with the rhythm sound off: with it on, the
  /// microphone would hear the phone playing every note perfectly.
  MicInput? _mic;
  StreamSubscription<Int16List>? _micSubscription;
  LiveJudge? _liveJudge;
  Timer? _judgingFinishTimer;

  /// Set while Start is waiting on the microphone, so a second tap doesn't
  /// start a second run.
  bool _starting = false;
  bool _micUnavailable = false;
  JudgedHit? _lastJudgement;

  /// How many judgements this run has produced -- gives each one shown its
  /// own identity, so two "Perfect"s in a row still animate as two.
  int _judgementCount = 0;

  /// How many hits the microphone has heard this run, judged or not -- for
  /// the light that flashes on each one.
  int _heardCount = 0;

  /// The run's tally, once it is over and every note has been settled.
  Map<Judgement, int>? _finalCounts;

  /// When each note of the score is due on this run's timeline, in seconds
  /// from the start of the count-in.
  List<double> _noteTimes = const [];

  /// Where the player's hits landed, as marks under the staff of the
  /// timeline measure (count-in = 0) each fell in.
  final Map<int, List<StaffMark>> _hitMarks = {};

  /// Everything the microphone heard this run, and every judgement made, so
  /// the run can be reviewed once it's over ([_review]).
  final _recording = <Int16List>[];
  final _runJudgements = <JudgedHit>[];

  /// The finished run, ready to go over on the review screen -- set only
  /// for a run that was judged.
  RunReview? _review;

  /// How the finished run's dynamics went -- worked out once per run.
  DynamicsCheck? get _dynamics {
    final review = _review;
    if (review == null) return null;
    if (!identical(_dynamicsOf, review)) {
      _dynamicsOf = review;
      _dynamicsCache = DynamicsCheck.of(review);
    }
    return _dynamicsCache;
  }

  RunReview? _dynamicsOf;
  DynamicsCheck? _dynamicsCache;

  /// The hairpins under each of the score's measures (not the count-in).
  late final List<List<HairpinSegment>> _hairpins = [
    for (var measure = 0; measure < widget.score.measures.length; measure++)
      widget.score.hairpinSegmentsIn(measure),
  ];

  late final PracticeHistoryStore _history = widget.historyStore ?? FilePracticeHistoryStore();

  /// When the current run started, for its history record.
  DateTime? _runStartedAt;

  /// The finished run being saved to the practice history (null for a run
  /// that isn't saved).
  Future<PracticeRun?>? _savedRun;

  /// The player's note about the finished run.
  String _runNote = '';

  /// This phone's sound delay as measured on earlier runs (see
  /// [MicLatencyHistory]), and as measured on this one once it's over.
  MicLatencyHistory _latencyHistory = MicLatencyHistory();
  double? _measuredDelaySeconds;

  /// The sound delay the player measured in calibration mode, if they have.
  /// Preferred over [_latencyHistory] for a run that can't hear its
  /// count-in: it was measured through whatever the player listens on,
  /// where the history only ever knows the phone's own speaker.
  double? _calibratedDelaySeconds;

  /// Finds the current run's microphone audio on the wall clock.
  RecordingClock _recordingClock = RecordingClock();

  /// How long after the timeline ends to keep listening before settling the
  /// tally: a hit on the very last note is only reported once the audio
  /// after it has arrived from the microphone and been analyzed.
  static const _judgingTailDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _practiceTempoBpm = widget.score.tempoBpm;
    _playbackController = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_onPlaybackTick)
      ..addStatusListener(_onPlaybackStatus);
    unawaited(_loadLatencyHistory());
    // For the whole time the screen is open, not just during a run: between
    // runs the player is reading the result and setting the next tempo,
    // sticks in hand.
    unawaited(widget.screenAwake.keep(true));
  }

  Future<void> _loadLatencyHistory() async {
    // Failing to load either only costs the fallback for a run whose
    // count-in isn't heard.
    try {
      final history = await widget.latencyStore.load();
      if (mounted) _latencyHistory = history;
    } catch (e) {
      debugPrint('Could not load the saved sound delay: $e');
    }
    try {
      final calibrated = await widget.calibrationStore.load();
      if (mounted) _calibratedDelaySeconds = calibrated;
    } catch (e) {
      debugPrint('Could not load the saved calibration: $e');
    }
  }

  @override
  void dispose() {
    _countInPositionSubscription?.cancel();
    _countInFallbackTimer?.cancel();
    _stopListening();
    _playbackController.dispose();
    _clickPlayer.dispose();
    unawaited(widget.screenAwake.keep(false));
    super.dispose();
  }

  /// Opens the microphone and sets up a judge for the run about to start.
  /// Leaves the run unjudged ([_micUnavailable]) if the microphone can't be
  /// used, rather than blocking practice.
  Future<void> _startListening() async {
    final mic = widget.createMicInput();
    try {
      if (!await mic.requestPermission()) {
        _micUnavailable = true;
        _releaseMic(mic);
        return;
      }
      final chunks = await mic.start();
      if (!mounted) {
        _releaseMic(mic);
        return;
      }
      final secondsPerUnit = _msPerUnit / 1000;
      final countInSeconds = _countInMeter.units * secondsPerUnit;
      _noteTimes = [
        for (final unit in widget.score.noteStartUnits) countInSeconds + unit * secondsPerUnit,
      ];
      _liveJudge = LiveJudge(
        sampleRate: mic.sampleRate,
        clickTimes: [
          for (var beat = 0; beat < _countInBeats; beat++) beat * _unitsPerBeat * secondsPerUnit,
        ],
        noteTimes: _noteTimes,
        rests: [
          for (final (start, end) in widget.score.restSpanUnits)
            (countInSeconds + start * secondsPerUnit, countInSeconds + end * secondsPerUnit),
        ],
        graceNotes: widget.score.graceNoteIndexes,
        judgingStartsAt: countInSeconds,
      );
      _recordingClock = RecordingClock();
      _heardCount = 0;
      _recording.clear();
      _runJudgements.clear();
      _noteColorsJudgementCount = -1; // a new run: recolour from scratch
      _mic = mic;
      _micSubscription = chunks.listen(
        _onMicSamples,
        onError: (Object e) => debugPrint('Practice microphone stream failed: $e'),
      );
    } catch (e) {
      debugPrint('Practice microphone failed to start: $e');
      _micUnavailable = true;
      _releaseMic(mic);
    }
  }

  void _onMicSamples(Int16List samples) {
    final judge = _liveJudge;
    final mic = _mic;
    if (judge == null || mic == null) return;

    _recordingClock.addChunk(samples.length, mic.sampleRate);
    _recording.add(samples);
    final clockStart = _timelineStartByClock;
    if (clockStart != null) {
      // Where the count-in should turn up: where the clocks put the start
      // of the timeline, plus the sound delay those clocks can't see.
      judge.expectTimelineStart(
        clockStart + (_calibratedDelaySeconds ?? _latencyHistory.typical ?? 0),
        trusted: _calibratedDelaySeconds != null || _latencyHistory.isReliable,
      );
    }

    final stateBefore = judge.state;
    final judged = judge.addSamples(samples);
    if (judged.isEmpty && judge.state == stateBefore && judge.hitsHeard == _heardCount) return;
    setState(() {
      _heardCount = judge.hitsHeard;
      _showJudged(judged);
    });
  }

  /// Where in the recording the timeline starts, going only by the app's
  /// own clocks: the moment the count-in audio reported starting, measured
  /// from the moment the microphone's audio began. Off from where the
  /// count-in is really heard by this phone's sound delay.
  double? get _timelineStartByClock {
    final anchor = _countInAnchor;
    return anchor == null ? null : _recordingClock.secondsAt(anchor);
  }

  /// Shows [judged] as the latest judgement and as marks under the staff.
  /// Must be called within `setState`.
  void _showJudged(List<JudgedHit> judged) {
    if (judged.isEmpty) return;
    _lastJudgement = judged.last;
    _judgementCount += judged.length;
    _runJudgements.addAll(judged);

    for (final hit in judged) {
      final (measureIndex, mark) = judgementMark(
        hit,
        layout: _layout,
        noteTimes: _noteTimes,
        secondsPerUnit: _msPerUnit / 1000,
        palette: AppPalette.of(context),
      );
      // A new list each time: the staff only redraws for a different list.
      _hitMarks[measureIndex] = [...?_hitMarks[measureIndex], mark];
    }
  }

  /// Packs up the run just finished for the review screen: its judgements,
  /// and the recording from the start of the count-in on, so the replay and
  /// the timeline line up second for second.
  RunReview? _buildReview(LiveJudge judge, int sampleRate) {
    final timelineStart = judge.timelineStart;
    if (timelineStart == null) return null;
    final totalSamples = _recording.fold(0, (sum, chunk) => sum + chunk.length);
    final all = Int16List(totalSamples);
    var offset = 0;
    for (final chunk in _recording) {
      all.setAll(offset, chunk);
      offset += chunk.length;
    }
    final from = (timelineStart * sampleRate).round().clamp(0, all.length);
    return RunReview(
      layout: _layout,
      secondsPerUnit: _msPerUnit / 1000,
      noteTimes: _noteTimes,
      judgements: _runJudgements,
      counts: judge.counts,
      audio: Int16List.fromList(Int16List.sublistView(all, from)),
      sampleRate: sampleRate,
      timingEstimated: judge.timingIsEstimated,
    );
  }

  /// Settles the notes still waiting for a hit and shows the run's tally.
  void _finishJudging() {
    final judge = _liveJudge;
    if (judge == null) return;
    final lastJudged = judge.finish();
    final counts = judge.state == LiveJudgeState.judging ? judge.counts : null;
    final sampleRate = _mic?.sampleRate;

    // A run that heard its count-in has measured the sound delay: how far
    // the clocks' idea of the timeline's start was from the real thing.
    final heardStart = judge.heardTimelineStart;
    final clockStart = _timelineStartByClock;
    double? measuredDelay;
    if (heardStart != null && clockStart != null) {
      measuredDelay = heardStart - clockStart;
      _latencyHistory = _latencyHistory.adding(measuredDelay);
      unawaited(
        widget.latencyStore.save(_latencyHistory).catchError((Object e) {
          debugPrint('Could not save the sound delay: $e');
        }),
      );
    }

    _stopListening();
    setState(() {
      _showJudged(lastJudged);
      _finalCounts = counts;
      _measuredDelaySeconds = measuredDelay;
      _review = counts == null || sampleRate == null ? null : _buildReview(judge, sampleRate);
    });
    _saveRun();
  }

  /// Adds the finished run to its track's practice history.
  void _saveRun() {
    final review = _review;
    final scoreId = widget.scoreId;
    if (review == null || scoreId == null) return;
    _savedRun = _history
        .save(
          scoreId: scoreId,
          review: review,
          tempoBpm: _practiceTempoBpm,
          startedAt: _runStartedAt ?? clock.now(),
          section: widget.section == null ? null : RunSection.of(widget.section!),
        )
        .then<PracticeRun?>((run) => run)
        .catchError((Object e) {
          debugPrint('Could not save the run to the practice history: $e');
          return null;
        });
  }

  /// Asks for a note about the finished run and saves it with the run.
  Future<void> _editRunNote() async {
    final note = await showRunNoteDialog(context, initial: _runNote);
    if (note == null || !mounted) return;
    setState(() => _runNote = note);
    final run = await _savedRun;
    if (run == null) return;
    try {
      await _history.updateNote(run, note);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(note.isEmpty ? 'Note removed' : 'Note saved')));
    } catch (e) {
      debugPrint('Could not save the note: $e');
    }
  }

  void _stopListening() {
    _judgingFinishTimer?.cancel();
    _judgingFinishTimer = null;
    _micSubscription?.cancel();
    _micSubscription = null;
    final mic = _mic;
    if (mic != null) _releaseMic(mic);
    _mic = null;
  }

  void _releaseMic(MicInput mic) {
    unawaited(
      mic.stop().catchError((Object e) {
        debugPrint('Practice microphone failed to stop: $e');
      }),
    );
  }

  double get _msPerUnit => widget.score.tempoBeat.msPerUnit(_practiceTempoBpm);

  String _labelFor(int timelineIndex) => _layout.labelFor(timelineIndex);

  Measure _measureFor(int timelineIndex) => _layout.measureAt(timelineIndex);

  void _onPlaybackTick() {
    final units = _playbackController.value * _totalUnits;
    final measureIndex = _timelineIndexAt(units);
    if (_slots.currentMeasureIndex != measureIndex) {
      _slots.advanceTo(measureIndex);
    }
    setState(() => _globalUnits = units);
  }

  void _onPlaybackStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() => _phase = _PracticePhase.done);
      if (_liveJudge != null) {
        _judgingFinishTimer = Timer(_judgingTailDelay, _finishJudging);
      }
    }
  }

  /// Renders the whole timeline's audio into a single buffer up front and
  /// plays it with one `play()` call -- triggering `play()` once per beat/
  /// note on the same player sounded uneven or dropped hits, since each call
  /// is an async platform-channel round-trip and back-to-back calls on the
  /// same player race each other (the same retrigger bug `RhythmPlayer` hit
  /// and fixed the same way; see also `RhythmPlayer._renderSequence`, which
  /// this mirrors for the 8 real measures' portion when [_rhythmSoundEnabled]
  /// is on).
  ///
  /// The count-in is always rendered in; the real measures' actual hit
  /// sounds are only mixed in when [_rhythmSoundEnabled] is on, so the same
  /// single audio player and calibration keeps driving the playhead either
  /// way -- there is no second, separately-clocked audio path to keep in
  /// sync.
  Future<Uint8List> _renderTimelineAudio() async {
    // Fractional, rounded per hit -- see `RhythmPlayer._renderSequence`.
    final samplesPerUnit = ClickSound.sampleRate * _msPerUnit / 1000;
    final countInClick = await ClickSound.normalSamples(widget.score.instrument);
    final rhythmNormal = _rhythmSoundEnabled
        ? await ClickSound.normalSamples(widget.score.instrument)
        : null;
    final rhythmAccent = _rhythmSoundEnabled
        ? await ClickSound.accentSamples(widget.score.instrument)
        : null;
    final rhythmMarcato = _rhythmSoundEnabled
        ? await ClickSound.marcatoSamples(widget.score.instrument)
        : null;
    final rhythmGrace = _rhythmSoundEnabled
        ? await ClickSound.graceSamples(widget.score.instrument)
        : null;

    final tailLength = [
      countInClick.length,
      rhythmNormal?.length ?? 0,
      rhythmAccent?.length ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final mixBuffer = Int32List((_totalUnits * samplesPerUnit).ceil() + tailLength);

    // [leadSamples] earlier than the position: a grace stroke before its
    // note. [gain]: turned up or down for the note's dynamics, never past
    // what the sound has room for.
    final headroom = <Int16List, double>{};
    void mixAt(int unitPosition, Int16List samples, {int leadSamples = 0, double gain = 1}) {
      ClickSound.mixInto(
        mixBuffer,
        (unitPosition * samplesPerUnit).round() - leadSamples,
        samples,
        gain: gain,
        headroom: gain > 1
            ? headroom.putIfAbsent(samples, () => ClickSound.headroom(samples))
            : double.infinity,
      );
    }

    for (var beat = 0; beat < _countInBeats; beat++) {
      mixAt(beat * _unitsPerBeat, countInClick);
    }

    if (_rhythmSoundEnabled) {
      final gains = ClickSound.dynamicGains(widget.score);
      var noteIndex = 0;
      for (var measureIndex = 0; measureIndex < widget.score.measures.length; measureIndex++) {
        final measure = widget.score.measures[measureIndex];
        var unitCursor = _timelineStarts[measureIndex + 1];
        for (final event in measure.events) {
          if (!event.isRest) {
            final gain = gains[noteIndex++];
            mixAt(
              unitCursor,
              ClickSound.samplesForType(
                event.type,
                normal: rhythmNormal!,
                accent: rhythmAccent!,
                marcato: rhythmMarcato!,
              ),
              gain: gain,
            );
            for (final units in ClickSound.rollStrokeUnits(event)) {
              mixAt(unitCursor + units, rhythmNormal, gain: gain);
            }
            // Always room for these: the count-in comes before every note.
            for (final lead in ClickSound.graceLeadSamples(event.ornament, _msPerUnit)) {
              mixAt(unitCursor, rhythmGrace!, leadSamples: lead, gain: gain);
            }
          }
          unitCursor += event.durationUnits;
        }
      }
    }

    final finalSamples = Int16List(mixBuffer.length);
    for (var i = 0; i < mixBuffer.length; i++) {
      finalSamples[i] = mixBuffer[i].clamp(-32768, 32767);
    }
    return ClickSound.pcm16ToWav(finalSamples);
  }

  /// Starts a run, first opening the microphone if the run is to be judged.
  /// The microphone has to be listening before the count-in sounds, since
  /// hearing the count-in is how hits get placed on the timeline (see
  /// [LiveJudge]) -- and the first time, that means waiting on the user to
  /// answer the permission prompt.
  Future<void> _onStartPressed() async {
    if (_starting) return;
    _micUnavailable = false;
    if (!_rhythmSoundEnabled) {
      _starting = true;
      await _startListening();
      _starting = false;
      if (!mounted) return;
    }
    _start();
  }

  /// Which run is current: bumped on every start and every stop, so audio
  /// still being prepared for a run that has since been stopped knows not
  /// to start playing once it's ready.
  int _runGeneration = 0;

  void _start() {
    _runGeneration++;
    _runStartedAt = clock.now();
    _slots.reset();
    setState(() => _phase = _PracticePhase.running);
    _countInAnchor = null;
    _countInPositionSubscription = _clickPlayer.onPositionChanged.listen(_onCountInPositionSample);
    // Fire-and-forget: the fallback timer below must not wait on this --
    // sample loading is real async I/O (a WAV asset, decoded on first use;
    // `ClickSound.preload()` in main() warms the cache ahead of time so this
    // is normally already resolved), unrelated to the "no audio position
    // ever arrived" case the fallback timer exists to handle.
    unawaited(_playTimelineAudio());
    _countInFallbackTimer = Timer(_countInFallbackDelay, () {
      if (_countInAnchor == null) _beginTimeline(clock.now());
    });
  }

  Future<void> _playTimelineAudio() async {
    final generation = _runGeneration;
    try {
      final timelineBytes = await _renderTimelineAudio();
      // Rendering takes a moment; Stop may have been pressed meanwhile.
      if (generation != _runGeneration || !mounted) return;
      await _clickPlayer.play(BytesSource(timelineBytes));
    } catch (e) {
      // Best-effort: the visual timeline still runs via the fallback timer
      // in _start() even with no audio, so a failure here shouldn't block
      // practice -- but it shouldn't be silent either.
      debugPrint('Practice timeline audio failed to play: $e');
    }
  }

  void _onCountInPositionSample(Duration position) {
    if (_countInAnchor != null || position < _minCountInStartupPosition) return;
    _beginTimeline(clock.now().subtract(position));
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
    final elapsedSinceAnchor = clock.now().difference(anchor);
    final startFraction =
        (elapsedSinceAnchor.inMicroseconds / _playbackController.duration!.inMicroseconds).clamp(
          0.0,
          1.0,
        );
    _playbackController.forward(from: startFraction);
  }

  void _returnToIdle() {
    // Stop means stop: the run's audio (the count-in, and the whole rhythm
    // when "Play rhythm sound" is on) would otherwise play on to its end.
    _runGeneration++;
    unawaited(
      _clickPlayer.stop().catchError((Object e) {
        debugPrint('Practice audio failed to stop: $e');
      }),
    );
    _countInPositionSubscription?.cancel();
    _countInPositionSubscription = null;
    _countInFallbackTimer?.cancel();
    _countInFallbackTimer = null;
    _countInAnchor = null;
    if (_playbackController.isAnimating) _playbackController.stop();
    _stopListening();
    _liveJudge = null;
    setState(() {
      _phase = _PracticePhase.idle;
      _slots.reset();
      _globalUnits = 0;
      _micUnavailable = false;
      _lastJudgement = null;
      _finalCounts = null;
      _measuredDelaySeconds = null;
      _hitMarks.clear();
      _review = null;
      _savedRun = null;
      _runNote = '';
      _recording.clear();
      _runJudgements.clear();
      _noteColorsJudgementCount = -1; // a new run: recolour from scratch
    });
  }

  /// Straight into another run, [_tempoStepBpm] faster.
  void _practiceAgainFaster() {
    _returnToIdle();
    _adjustTempo(_tempoStepBpm);
    unawaited(_onStartPressed());
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

  /// Why the current run isn't being judged, when it was meant to be.
  String? get _judgingNotice {
    if (_phase == _PracticePhase.idle) return null;
    if (_micUnavailable) return 'Microphone unavailable. This run is not judged.';
    if (_liveJudge?.state == LiveJudgeState.countInNotHeard) {
      return 'Could not hear the count-in. This run is not judged.';
    }
    return null;
  }

  /// How this run's hits are being placed on the timeline, once that's
  /// worth saying: by estimate while it's happening, and either way at the
  /// end.
  String? get _alignmentDetail {
    final counts = _finalCounts;
    final accuracy = counts == null ? null : runAccuracy(counts);
    final alignment = _alignmentOnly;
    if (accuracy == null) return alignment;
    return 'Accuracy ${accuracyText(accuracy)}${alignment == null ? '' : '  ·  $alignment'}';
  }

  String? get _alignmentOnly {
    if (_liveJudge?.timingIsEstimated ?? false) {
      return _calibratedDelaySeconds != null
          ? 'Count-in not heard. Timing from your calibration.'
          : 'Count-in not heard. Timing estimated from earlier runs.';
    }
    final delay = _measuredDelaySeconds;
    if (delay != null) return 'Count-in heard. Sound delay ${(delay * 1000).round()} ms.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Practice: ${widget.score.title}')),
      body: _withConfetti(
        context,
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Once a run starts, everything the player needs while playing --
              // the judgement and all three measures -- has to be on screen at
              // once: they can't stop to scroll. So the settings (which are
              // locked during a run anyway) are hidden, and the staffs shrink to
              // fit if they must. Before a run, the same goes for the settings
              // and the Start button: the judgement strip (empty until a run)
              // is left out and the staffs shrink instead. Scrolling stays as a
              // last resort for a screen too short even for that.
              final playing = _phase != _PracticePhase.idle;
              final staffHeight = _staffHeightToFit(constraints.maxHeight, playing: playing);
              final noteColors = SettingsScope.of(context).colorNotesByJudgement
                  ? _noteColors()
                  : const <int, Map<int, Color>>{};
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: _verticalPadding),
                child: Column(
                  children: [
                    if (playing)
                      _JudgementBanner(
                        lastJudgement: _lastJudgement,
                        judgementCount: _judgementCount,
                        finalCounts: _finalCounts,
                        notice: _judgingNotice,
                        detail: _alignmentDetail,
                      ),
                    if (playing)
                      TimingNeedle(key: const Key('practice_timing_needle'), hits: _recentHits()),
                    // The light balanced by a gap of its width on the other
                    // side, so the status stays centred.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: MicLight.width),
                        Text(
                          _statusText,
                          key: const Key('practice_status_text'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        MicLight(
                          key: const Key('practice_mic_light'),
                          heardCount: _heardCount,
                          listening: _mic != null,
                        ),
                      ],
                    ),
                    if (!playing) ...[
                      _TempoStepper(
                        beat: widget.score.tempoBeat,
                        bpm: _practiceTempoBpm,
                        enabled: true,
                        onDecrease: () => _adjustTempo(-_tempoStepBpm),
                        onIncrease: () => _adjustTempo(_tempoStepBpm),
                        onTapTempo: (bpm) => setState(() => _practiceTempoBpm = bpm),
                      ),
                      SwitchListTile(
                        key: const Key('practice_rhythm_sound_toggle'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        minTileHeight: 48,
                        minVerticalPadding: 0,
                        contentPadding: EdgeInsets.zero,
                        // One line rather than a subtitle, so Start fits on
                        // a small phone without scrolling.
                        title: const Text('Play rhythm sound (not judged)'),
                        value: _rhythmSoundEnabled,
                        onChanged: (value) => setState(() => _rhythmSoundEnabled = value),
                      ),
                    ],
                    const SizedBox(height: _gapAboveSlots),
                    // Stacked full-width, one measure per row (like systems in
                    // sheet music) rather than side-by-side: splitting the screen
                    // width 3 ways left too little room between notes to read.
                    Column(
                      children: PracticeSlot.values.map((slot) {
                        final timelineIndex = _slots.content[slot];
                        final isActive =
                            timelineIndex != null && timelineIndex == _slots.currentMeasureIndex;
                        final playheadUnits = isActive
                            ? _globalUnits - _timelineStarts[timelineIndex]
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: _gapBetweenSlots),
                          child: _PracticeSlotView(
                            key: Key('practice_slot_${slot.name}'),
                            label: timelineIndex == null ? '' : _labelFor(timelineIndex),
                            measureIndex: timelineIndex,
                            measure: timelineIndex != null ? _measureFor(timelineIndex) : null,
                            showTimeSignature:
                                timelineIndex != null && _showsTimeSignature(timelineIndex),
                            isActive: isActive,
                            playheadUnits: playheadUnits,
                            marks: _hitMarks[timelineIndex] ?? const [],
                            eventColors: noteColors[timelineIndex] ?? const {},
                            hairpins: timelineIndex == null || timelineIndex == 0
                                ? const []
                                : _hairpins[timelineIndex - 1],
                            staffHeight: staffHeight,
                          ),
                        );
                      }).toList(),
                    ),
                    _buildActionButton(),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// [body], with confetti falling over it when the run just finished
  /// deserves it (and the player hasn't turned it off): one above 90%
  /// accuracy, or more of it for one all Perfect. A run that wasn't judged
  /// never gets it.
  Widget _withConfetti(BuildContext context, Widget body) {
    final counts = _finalCounts;
    final accuracy = counts == null ? null : runAccuracy(counts);
    final celebrate =
        _phase == _PracticePhase.done &&
        accuracy != null &&
        accuracy > _confettiAccuracy &&
        SettingsScope.of(context).confetti;
    if (!celebrate) return body;
    final perfect = counts!.entries.every(
      (entry) => entry.key == Judgement.perfect || entry.value == 0,
    );
    return Stack(
      children: [
        body,
        Positioned.fill(
          child: ConfettiBurst(
            // A new burst for each run.
            key: ValueKey(('confetti', _runGeneration)),
            perfect: perfect,
          ),
        ),
      ],
    );
  }

  /// A run more accurate than this ([runAccuracy]) gets confetti.
  static const _confettiAccuracy = 0.9;

  /// Each judged note's colour, for the "colour notes by judgement"
  /// setting. Worked out again only when a new judgement arrives, not on
  /// every frame of the moving playhead -- the same map, unchanged, also
  /// spares the staffs a redraw.
  Map<int, Map<int, Color>> _noteColors() {
    final palette = AppPalette.of(context);
    if (_noteColorsJudgementCount != _runJudgements.length || _noteColorsPalette != palette) {
      _noteColorsJudgementCount = _runJudgements.length;
      _noteColorsPalette = palette;
      _noteColorsCache = judgementEventColors(
        _runJudgements,
        layout: _layout,
        secondsPerUnit: _msPerUnit / 1000,
        palette: palette,
      );
    }
    return _noteColorsCache;
  }

  /// The latest hits for the timing needle -- worked out again only when a
  /// new judgement arrives, so the needle isn't redrawn on every frame.
  List<JudgedHit> _recentHits() {
    if (_recentHitsJudgementCount != _runJudgements.length) {
      _recentHitsJudgementCount = _runJudgements.length;
      _recentHitsCache = TimingNeedle.recent(_runJudgements);
    }
    return _recentHitsCache;
  }

  List<JudgedHit> _recentHitsCache = const [];
  int _recentHitsJudgementCount = 0;

  Map<int, Map<int, Color>> _noteColorsCache = const {};
  int _noteColorsJudgementCount = 0;
  AppPalette? _noteColorsPalette;

  static const double _verticalPadding = 8;
  static const double _gapAboveSlots = 4;
  static const double _gapBetweenSlots = 6;

  /// The tallest staff (up to the usual height) that lets the layout --
  /// the playing one, or the one before a run -- fit in [availableHeight]
  /// without scrolling, or the smallest staff that still draws everything
  /// if nothing fits.
  ///
  /// Adds up each layout's fixed parts by hand; the "fits on a phone" tests
  /// in `practice_screen_test.dart` are what keep these numbers honest.
  static double _staffHeightToFit(double availableHeight, {required bool playing}) {
    const sharedHeight =
        _verticalPadding * 2 +
        24 // status text
        +
        _gapAboveSlots +
        48 // action button, with its tap-target padding
        +
        8 // space below the button
        +
        4; // margin for rounding
    const playingHeight = sharedHeight + _JudgementBanner.height + TimingNeedle.height;
    const idleHeight =
        sharedHeight +
        57 // tempo stepper (its tempo mark is the tallest part)
        +
        48; // rhythm sound switch
    final fixedHeight = playing ? playingHeight : idleHeight;
    const perSlotOverhead = _PracticeSlotView.chromeHeight + _gapBetweenSlots;
    final perStaff = (availableHeight - fixedHeight) / PracticeSlot.values.length - perSlotOverhead;
    return perStaff.clamp(StaffNotationView.minHeight, StaffNotationView.defaultHeight).toDouble();
  }

  Widget _buildActionButton() {
    switch (_phase) {
      case _PracticePhase.idle:
        return ElevatedButton.icon(
          key: const Key('practice_start_button'),
          onPressed: _onStartPressed,
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
        final review = _review;
        final fasterTempo = (_practiceTempoBpm + _tempoStepBpm).clamp(_minTempoBpm, _maxTempoBpm);
        final canGoFaster = fasterTempo > _practiceTempoBpm;
        final counts = _finalCounts;
        final accuracy = counts == null ? null : runAccuracy(counts);
        // A good enough run makes going faster the main button; otherwise
        // it's the same tempo again.
        final readyForFaster =
            canGoFaster && accuracy != null && accuracy >= _readyForFasterAccuracy;
        final again = readyForFaster ? OutlinedButton.icon : ElevatedButton.icon;
        final faster = readyForFaster ? ElevatedButton.icon : OutlinedButton.icon;
        final buttons = Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            again(
              key: const Key('practice_again_button'),
              onPressed: _returnToIdle,
              icon: const Icon(Icons.replay),
              label: const Text('Practice Again'),
            ),
            if (canGoFaster)
              faster(
                key: const Key('practice_again_faster_button'),
                onPressed: _practiceAgainFaster,
                icon: const Icon(Icons.fast_forward),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Again at '),
                    TempoMark(beat: widget.score.tempoBeat, bpm: fasterTempo),
                  ],
                ),
              ),
            if (review != null)
              OutlinedButton.icon(
                key: const Key('practice_review_button'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReviewScreen(review: review, note: _runNote),
                  ),
                ),
                icon: const Icon(Icons.insights),
                label: const Text('Review'),
              ),
            if (review != null && widget.scoreId != null)
              OutlinedButton.icon(
                key: const Key('practice_note_button'),
                onPressed: _editRunNote,
                icon: const Icon(Icons.edit_note),
                label: Text(_runNote.isEmpty ? 'Add note' : 'Edit note'),
              ),
          ],
        );
        final dynamics = _dynamics;
        final dynamicsLine = dynamics == null ? null : dynamicsSummary(dynamics);
        if (!readyForFaster && dynamicsLine == null) return buttons;
        return Column(
          children: [
            if (dynamicsLine != null) ...[
              Text(
                '$dynamicsLine -- see Review',
                key: const Key('practice_dynamics_summary'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            if (readyForFaster) ...[
              DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.titleMedium,
                child: Row(
                  key: const Key('practice_ready_faster'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${accuracyText(accuracy)}. Ready for '),
                    TempoMark(beat: widget.score.tempoBeat, bpm: fasterTempo),
                    const Text('?'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            buttons,
          ],
        );
    }
  }
}

/// The strip at the top of the practice screen: the judgement of the
/// player's latest hit while a run is on, the run's tally once it is over,
/// or the reason the run isn't being judged. Always the same height, so the
/// staff below doesn't jump as judgements come and go.
class _JudgementBanner extends StatelessWidget {
  final JudgedHit? lastJudgement;
  final int judgementCount;
  final Map<Judgement, int>? finalCounts;
  final String? notice;

  /// A small second line under the judgement or tally.
  final String? detail;

  const _JudgementBanner({
    required this.lastJudgement,
    required this.judgementCount,
    required this.finalCounts,
    required this.notice,
    required this.detail,
  });

  static const double height = 68;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _content(context, textTheme),
          if (detail != null && notice == null)
            Text(
              detail!,
              key: const Key('practice_alignment_detail'),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, TextTheme textTheme) {
    final counts = finalCounts;
    if (counts != null) {
      // Shrunk rather than wrapped if it doesn't fit on one line.
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          Judgement.values.map((j) => '${judgementLabel(j)} ${counts[j]}').join('  ·  '),
          key: const Key('practice_judgement_summary'),
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
      );
    }
    if (notice != null) {
      return Text(
        notice!,
        key: const Key('practice_judging_notice'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final hit = lastJudgement;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 1.4, end: 1.0).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: hit == null
          ? const SizedBox.shrink()
          : Text(
              judgementLabelWithDirection(hit),
              key: ValueKey(judgementCount),
              style: textTheme.headlineMedium?.copyWith(
                color: judgementColor(hit.judgement, AppPalette.of(context)),
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}

class _TempoStepper extends StatelessWidget {
  /// Shown as a tempo mark, so the player knows which note they're
  /// counting (and tapping) at this speed.
  final TempoBeat beat;
  final int bpm;
  final bool enabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  /// Gets the tempo the player tapped, in the score's beat note.
  final ValueChanged<int> onTapTempo;

  const _TempoStepper({
    required this.onTapTempo,
    required this.beat,
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
          width: 120,
          child: Center(
            child: TempoMark(
              key: const Key('practice_tempo_value'),
              beat: beat,
              bpm: bpm,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        IconButton(
          key: const Key('practice_tempo_increase'),
          onPressed: enabled ? onIncrease : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
        const SizedBox(width: 4),
        TapTempoButton(
          key: const Key('practice_tap_tempo'),
          minBpm: _PracticeScreenState._minTempoBpm,
          maxBpm: _PracticeScreenState._maxTempoBpm,
          enabled: enabled,
          onTempo: onTapTempo,
        ),
      ],
    );
  }
}

class _PracticeSlotView extends StatelessWidget {
  final String label;
  final int? measureIndex;
  final Measure? measure;
  final bool showTimeSignature;
  final bool isActive;
  final double? playheadUnits;
  final List<StaffMark> marks;
  final Map<int, Color> eventColors;
  final List<HairpinSegment> hairpins;
  final double staffHeight;

  /// Height of everything but the staff: the label line, the padding, and
  /// the highlight border.
  static const double chromeHeight = 16 + 2 * 4 + 2 * 2;

  const _PracticeSlotView({
    super.key,
    required this.label,
    required this.measureIndex,
    required this.measure,
    required this.showTimeSignature,
    required this.isActive,
    required this.playheadUnits,
    required this.marks,
    required this.eventColors,
    required this.hairpins,
    required this.staffHeight,
  });

  @override
  Widget build(BuildContext context) {
    final highlightColor = AppPalette.of(context).accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(color: isActive ? highlightColor : Colors.transparent, width: 2),
          color: isActive ? highlightColor.withValues(alpha: 0.08) : null,
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: measureIndex == null
                  ? SizedBox(key: const ValueKey('blank'), height: staffHeight)
                  : StaffNotationView(
                      key: ValueKey(measureIndex),
                      measure: measure!,
                      showTimeSignature: showTimeSignature,
                      playheadUnits: playheadUnits,
                      marks: marks,
                      eventColors: eventColors,
                      hairpins: hairpins,
                      height: staffHeight,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
