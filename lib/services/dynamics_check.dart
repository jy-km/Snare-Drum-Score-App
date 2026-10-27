import 'dart:math' as math;
import 'dart:typed_data';

import '../models/rhythm_score.dart';
import 'hit_judge.dart';
import 'run_review.dart';

/// How the dynamics written in a score were played, worked out from a
/// finished run's recording.
///
/// Nothing is measured against a fixed loudness: what "p" or "f" is depends
/// on the drum, the room, the phone and the player. Instead the player's own
/// playing sets the scale -- each stretch under a marking gets a level
/// (how loud its hits were, in decibels), and each change of marking is
/// judged by whether the level moved the way it should: louder from p to f,
/// softer from f to p. Crescendos and decrescendos are judged by whether
/// their hits got louder or softer from start to end.
class DynamicsCheck {
  /// How far the level has to move, either way, for a change to count --
  /// smaller differences are hard to hear and easily come from where the
  /// stick lands.
  static const double minChangeDb = 2;

  /// The fewest hits a hairpin needs before getting louder or softer across
  /// it can be judged.
  static const int minHairpinHits = 3;

  /// The fewest hits a stretch under a marking needs to get a level.
  static const int minSectionHits = 1;

  final List<DynamicSection> sections;

  /// Between each two stretches next to each other with different
  /// markings -- judged only when the score has two markings or more.
  final List<DynamicChange> changes;

  final List<HairpinCheck> hairpins;

  const DynamicsCheck._(this.sections, this.changes, this.hairpins);

  /// Whether the score has anything to judge: two markings or more, or a
  /// hairpin.
  bool get hasChecks => changes.isNotEmpty || hairpins.isNotEmpty;

  /// The checks that could be judged (enough hits), and how many of those
  /// were played as written.
  int get judged =>
      changes.where((change) => change.met != null).length +
      hairpins.where((hairpin) => hairpin.met != null).length;
  int get met =>
      changes.where((change) => change.met == true).length +
      hairpins.where((hairpin) => hairpin.met == true).length;

  /// The loudest stretch's level, which the others are given relative to.
  double? get loudestDb {
    final levels = [for (final section in sections) ?section.levelDb];
    return levels.isEmpty ? null : levels.reduce(math.max);
  }

  factory DynamicsCheck.of(RunReview review) {
    final score = review.layout.score;
    final notes = score.notes;
    final spans = score.hairpinSpans;
    final inHairpin = {
      for (final span in spans)
        for (var note = span.firstNote; note <= span.lastNote; note++) note,
    };

    // How loud each played note was, by note index.
    final loudness = <int, double>{};
    for (final hit in review.judgements) {
      final note = hit.noteIndex;
      final time = hit.hitTimeSeconds;
      if (note == null || time == null || hit.judgement == Judgement.fail) continue;
      final db = hitLoudnessDb(review.audio, review.sampleRate, time);
      if (db != null) loudness[note] = db;
    }
    // Accented notes are meant to stand out of their marking's level, so
    // they don't set it.
    bool plain(int note) => notes[note].type == EventType.normal;

    final sections = <DynamicSection>[];
    for (var note = 0; note < notes.length; note++) {
      final mark = notes[note].dynamicMark;
      if (mark == null) continue;
      var last = note;
      while (last + 1 < notes.length && notes[last + 1].dynamicMark == null) {
        last++;
      }
      final levels = [
        for (var index = note; index <= last; index++)
          if (plain(index) && !inHairpin.contains(index) && loudness[index] != null)
            loudness[index]!,
      ];
      // A stretch that's all hairpin is judged by its hairpin; failing that,
      // its notes in the hairpin still give it a level.
      if (levels.isEmpty) {
        for (var index = note; index <= last; index++) {
          if (plain(index) && loudness[index] != null) levels.add(loudness[index]!);
        }
      }
      sections.add(
        DynamicSection(
          mark,
          firstNote: note,
          lastNote: last,
          levelDb: levels.length >= minSectionHits ? _median(levels) : null,
          hits: levels.length,
        ),
      );
    }

    final changes = <DynamicChange>[];
    for (var index = 1; index < sections.length; index++) {
      final from = sections[index - 1];
      final to = sections[index];
      if (from.mark == to.mark) continue;
      changes.add(DynamicChange(from, to));
    }

    final hairpins = <HairpinCheck>[];
    for (final span in spans) {
      final points = <(double, double)>[
        for (var note = span.firstNote; note <= span.lastNote; note++)
          if (plain(note) && loudness[note] != null) (review.noteTimes[note], loudness[note]!),
      ];
      hairpins.add(HairpinCheck(span, points.length >= minHairpinHits ? _rise(points) : null));
    }

    return DynamicsCheck._(sections, changes, hairpins);
  }

  /// How loud the hit at [timeSeconds] into [audio] was, in decibels below
  /// the loudest a recording can be (so always 0 or less): the loudest
  /// 10ms stretch from just before the hit to just after it. Null for
  /// silence, or a time outside the recording.
  static double? hitLoudnessDb(Int16List audio, int sampleRate, double timeSeconds) {
    final frame = (0.010 * sampleRate).round();
    final step = math.max(1, frame ~/ 2);
    final from = ((timeSeconds - 0.010) * sampleRate).round().clamp(0, audio.length);
    final to = ((timeSeconds + 0.050) * sampleRate).round().clamp(0, audio.length);
    var loudest = 0.0;
    for (var start = from; start + frame <= to; start += step) {
      var sum = 0.0;
      for (var i = start; i < start + frame; i++) {
        sum += audio[i] * audio[i].toDouble();
      }
      loudest = math.max(loudest, math.sqrt(sum / frame));
    }
    if (loudest <= 0) return null;
    return 20 * math.log(loudest / 32768) / math.ln10;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// How much louder (or, negative, softer) the straight line best through
  /// [points] (time, level) gets from the first time to the last.
  static double _rise(List<(double, double)> points) {
    final n = points.length;
    final meanX = points.fold(0.0, (sum, p) => sum + p.$1) / n;
    final meanY = points.fold(0.0, (sum, p) => sum + p.$2) / n;
    var covariance = 0.0;
    var variance = 0.0;
    for (final (x, y) in points) {
      covariance += (x - meanX) * (y - meanY);
      variance += (x - meanX) * (x - meanX);
    }
    if (variance == 0) return 0;
    return covariance / variance * (points.last.$1 - points.first.$1);
  }
}

/// The stretch of notes played under one marking: from the note it's
/// written at to the note before the next marking.
class DynamicSection {
  final DynamicMark mark;
  final int firstNote;
  final int lastNote;

  /// How loud it was played (the middle of its hits' levels), in decibels
  /// -- only meaningful next to the other sections' -- or null if too few
  /// of its notes were played.
  final double? levelDb;

  /// How many hits set [levelDb].
  final int hits;

  const DynamicSection(
    this.mark, {
    required this.firstNote,
    required this.lastNote,
    required this.levelDb,
    required this.hits,
  });
}

/// One change of marking, and how the level moved across it.
class DynamicChange {
  final DynamicSection from;
  final DynamicSection to;

  const DynamicChange(this.from, this.to);

  /// Whether the marking asks for louder (rather than softer).
  bool get louder => to.mark.index > from.mark.index;

  /// How much louder (or, negative, softer) it was played, in decibels; null
  /// if either side has no level.
  double? get differenceDb {
    final fromDb = from.levelDb;
    final toDb = to.levelDb;
    return fromDb == null || toDb == null ? null : toDb - fromDb;
  }

  /// Whether the level moved the way the marking asks, by enough to hear;
  /// null when it couldn't be judged.
  bool? get met {
    final difference = differenceDb;
    if (difference == null) return null;
    return louder
        ? difference >= DynamicsCheck.minChangeDb
        : difference <= -DynamicsCheck.minChangeDb;
  }
}

/// One crescendo or decrescendo, and how the level moved across it.
class HairpinCheck {
  final HairpinSpan span;

  /// How much louder (or, negative, softer) its hits got from start to end,
  /// in decibels -- or null if too few of its notes were played.
  final double? changeDb;

  const HairpinCheck(this.span, this.changeDb);

  bool? get met {
    final change = changeDb;
    if (change == null) return null;
    return span.kind == Hairpin.crescendo
        ? change >= DynamicsCheck.minChangeDb
        : change <= -DynamicsCheck.minChangeDb;
  }
}
