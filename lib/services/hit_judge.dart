/// How a note was played -- or, for [fail], that something was played
/// where nothing should have been.
enum Judgement {
  perfect,
  great,
  good,
  miss,

  /// A hit during a rest. Not a judgement of a note: it has no timing
  /// window, and fails are counted on top of the one-judgement-per-note
  /// tally rather than as part of it.
  fail,
}

extension JudgementWindow on Judgement {
  /// Whether this judges a note -- every note gets exactly one of these.
  bool get judgesANote => this != Judgement.fail;

  /// The furthest a hit can be from its note, early or late, and still earn
  /// this judgement. A hit further than [Judgement.good]'s window from every
  /// note is a miss. [Judgement.fail] has no window: it is about where a
  /// hit lands (in a rest), not how far it is from a note.
  double get windowSeconds {
    switch (this) {
      case Judgement.perfect:
        return 0.040;
      case Judgement.great:
        return 0.080;
      case Judgement.good:
        return 0.120;
      case Judgement.miss:
      case Judgement.fail:
        return double.infinity;
    }
  }

  static Judgement forOffset(double offsetSeconds) {
    final distance = offsetSeconds.abs();
    for (final judgement in [Judgement.perfect, Judgement.great, Judgement.good]) {
      if (distance <= judgement.windowSeconds) return judgement;
    }
    return Judgement.miss;
  }
}

/// One judgement: of a note (the hit that was paired with it, or its miss),
/// or a [Judgement.fail] for a hit during a rest.
class JudgedHit {
  final Judgement judgement;

  /// Index of the note this is about (into the times given to [HitJudge]).
  /// Null only for a fail, which belongs to no note.
  final int? noteIndex;

  /// Hit time minus note time -- negative is early, positive is late. Null
  /// for a note never hit, and for a fail.
  final double? offsetSeconds;

  /// When the hit happened, on the same clock as the note times given to
  /// [HitJudge]. Null for a note never hit.
  final double? hitTimeSeconds;

  const JudgedHit(this.judgement, {this.noteIndex, this.offsetSeconds, this.hitTimeSeconds});

  @override
  String toString() =>
      'JudgedHit(${judgement.name}, note: $noteIndex, '
      'offset: ${offsetSeconds == null ? null : '${(offsetSeconds! * 1000).round()}ms'})';
}

/// Judges hits against the notes of a score as they come in.
///
/// Every note gets exactly one judgement, and keeps the first one it gets:
/// each hit is paired with the nearest note that is still waiting for one
/// and within the Good window, and is judged by its distance from that
/// note; a note is judged a miss once time has moved past its Good window
/// with no hit paired to it ([advanceTo]). A hit with no such note -- a
/// second hit on a note already judged, or a sound nowhere near a note --
/// can't take away a judgement a note already has, and it isn't a note, so
/// it can't add a note judgement of its own. By the end ([finish]), the note
/// judgements add up to exactly the number of notes.
///
/// Such a hit that lands during a rest is a [Judgement.fail] instead --
/// playing where the score says not to. Fails sit outside the note tally:
/// any number of them can happen, and they never change a note's judgement.
/// A hit that can be paired with a note always is, even if it falls inside
/// the rest just before or after that note (e.g. an early hit on the note
/// after a rest is that note's Good-, not a fail). Any other hit -- one
/// outside every rest, such as a second hit on a note while it still
/// sounds -- is not judged at all.
///
/// A note with grace strokes before it (a flam or drag) is still one note
/// with one judgement: the strokes leading into it are part of it, not hits
/// of their own. So an early hit on such a note isn't judged on the spot --
/// it may be a grace stroke, with the note itself still to come. It is held
/// until the next hit on that note, or until the note's window closes, and
/// the note is then judged by whichever of its hits was closest. A grace
/// stroke therefore never makes its note early, and is never a fail.
///
/// Hits must be added in time order, and before [advanceTo] is called with
/// a time later than the hit.
class HitJudge {
  final List<double> _noteTimes;
  final List<bool> _judged;
  final Set<int> _graceNotes;

  /// For a note with grace strokes: the closest early hit on it so far,
  /// while the note waits to see whether a closer one follows.
  final Map<int, double> _heldHits = {};

  /// Every note before this index has been judged.
  int _firstOpenNote = 0;

  final List<(double, double)> _rests;

  final Map<Judgement, int> _counts = {for (final judgement in Judgement.values) judgement: 0};

  /// [noteTimes] is when each note should be hit, in seconds, ascending.
  /// [rests] are the stretches (start, end) where nothing should be played,
  /// on the same clock. [graceNotes] are the indexes of the notes that have
  /// grace strokes before them.
  HitJudge(
    List<double> noteTimes, {
    List<(double, double)> rests = const [],
    Set<int> graceNotes = const {},
  }) : _noteTimes = List.unmodifiable(noteTimes),
       _judged = List.filled(noteTimes.length, false),
       _rests = List.unmodifiable(rests),
       _graceNotes = Set.unmodifiable(graceNotes);

  /// How many notes have earned each judgement so far -- and, under
  /// [Judgement.fail], how many hits landed in rests.
  Map<Judgement, int> get counts => Map.unmodifiable(_counts);

  /// Judges the note [hitTime] goes with; failing that, returns a fail if
  /// it landed in a rest; otherwise returns null. Also returns null for an
  /// early hit on a note with grace strokes, which is held for now (see the
  /// class comment).
  JudgedHit? addHit(double hitTime) {
    final goodWindow = Judgement.good.windowSeconds;
    int? nearest;
    for (var i = _firstOpenNote; i < _noteTimes.length; i++) {
      if (_noteTimes[i] > hitTime + goodWindow) break;
      if (_judged[i] || _noteTimes[i] < hitTime - goodWindow) continue;
      if (nearest == null ||
          (_noteTimes[i] - hitTime).abs() < (_noteTimes[nearest] - hitTime).abs()) {
        nearest = i;
      }
    }

    if (nearest == null) {
      final inRest = _rests.any((rest) => hitTime >= rest.$1 && hitTime < rest.$2);
      return inRest ? _record(JudgedHit(Judgement.fail, hitTimeSeconds: hitTime)) : null;
    }
    if (_graceNotes.contains(nearest)) {
      final noteTime = _noteTimes[nearest];
      final held = _heldHits[nearest];
      final closest = held == null || (hitTime - noteTime).abs() <= (held - noteTime).abs()
          ? hitTime
          : held;
      if (hitTime < noteTime) {
        _heldHits[nearest] = closest;
        return null;
      }
      _heldHits.remove(nearest);
      return _judgeNote(nearest, closest);
    }
    return _judgeNote(nearest, hitTime);
  }

  JudgedHit _judgeNote(int noteIndex, double hitTime) {
    _judged[noteIndex] = true;
    final offset = hitTime - _noteTimes[noteIndex];
    return _record(
      JudgedHit(
        JudgementWindow.forOffset(offset),
        noteIndex: noteIndex,
        offsetSeconds: offset,
        hitTimeSeconds: hitTime,
      ),
    );
  }

  /// Settles every note whose Good window closed before [time] without
  /// being judged, and returns the judgements in note order: a miss, or --
  /// for a note with grace strokes whose only hits were early -- the
  /// judgement of the closest of them.
  List<JudgedHit> advanceTo(double time) {
    final misses = <JudgedHit>[];
    for (var i = _firstOpenNote; i < _noteTimes.length; i++) {
      if (_noteTimes[i] + Judgement.good.windowSeconds >= time) break;
      if (_judged[i]) continue;
      final held = _heldHits.remove(i);
      if (held != null) {
        misses.add(_judgeNote(i, held));
        continue;
      }
      _judged[i] = true;
      misses.add(_record(JudgedHit(Judgement.miss, noteIndex: i)));
    }
    while (_firstOpenNote < _noteTimes.length && _judged[_firstOpenNote]) {
      _firstOpenNote++;
    }
    return misses;
  }

  /// Settles every note still waiting: see [advanceTo].
  List<JudgedHit> finish() => advanceTo(double.infinity);

  JudgedHit _record(JudgedHit hit) {
    _counts[hit.judgement] = _counts[hit.judgement]! + 1;
    return hit;
  }
}
