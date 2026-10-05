import 'package:flutter/material.dart';

import '../services/hit_judge.dart';
import '../services/timeline_layout.dart';
import 'staff_notation_view.dart';

/// How judgements look, wherever they're shown -- practice and review alike.
String judgementLabel(Judgement judgement) {
  switch (judgement) {
    case Judgement.perfect:
      return 'Perfect';
    case Judgement.great:
      return 'Great';
    case Judgement.good:
      return 'Good';
    case Judgement.miss:
      return 'Miss';
    case Judgement.fail:
      return 'Fail';
  }
}

/// The label for one judged hit: a Great or Good also says which way the
/// hit was off -- "-" for early, "+" for late, the sign of its offset from
/// the note. A Perfect is close enough not to need correcting, and a Miss
/// or Fail has no note it can be early or late for.
String judgementLabelWithDirection(JudgedHit hit) {
  final label = judgementLabel(hit.judgement);
  final offset = hit.offsetSeconds;
  if (!_showsDirection(hit) || offset == null) return label;
  return offset < 0 ? '$label-' : '$label+';
}

bool _showsDirection(JudgedHit hit) =>
    hit.judgement == Judgement.great || hit.judgement == Judgement.good;

Color judgementColor(Judgement judgement) {
  switch (judgement) {
    case Judgement.perfect:
      return Colors.amber.shade800;
    case Judgement.great:
      return Colors.green.shade700;
    case Judgement.good:
      return Colors.blue.shade700;
    case Judgement.miss:
      return Colors.red.shade700;
    case Judgement.fail:
      // Crimson, darkened and pulled toward purple so it reads apart from
      // Miss's red even at a glance.
      return const Color(0xFF8E0E3A);
  }
}

/// A hit's signed timing error in whole milliseconds, e.g. "+62 ms" (late)
/// or "-48 ms" (early).
String offsetText(double offsetSeconds) {
  final ms = (offsetSeconds * 1000).round();
  return '${ms > 0 ? '+' : ''}$ms ms';
}

/// Where to mark [hit] on the timeline: which timeline measure's staff it
/// goes under, and the mark itself. A hit is marked where it landed; a note
/// nobody hit, where it was due. [noteTimes] and [secondsPerUnit] put the
/// run's seconds on [layout]'s units.
///
/// With [withOffset], a Great or Good is also labelled with its timing
/// error in milliseconds (e.g. "+62") -- too much to read while playing,
/// but what a review is for.
(int, StaffMark) judgementMark(
  JudgedHit hit, {
  required TimelineLayout layout,
  required List<double> noteTimes,
  required double secondsPerUnit,
  bool withOffset = false,
}) {
  final noteIndex = hit.noteIndex;
  final noteSeconds = noteIndex == null ? null : noteTimes[noteIndex];
  final units = (hit.hitTimeSeconds ?? noteSeconds!) / secondsPerUnit;
  // A hit goes on its note's staff even if it fell just the other side of
  // the barline -- a slightly early hit on beat 1 belongs beside beat 1, not
  // at the far end of the previous measure. (Notes sit on whole units;
  // rounding undoes the trip through seconds.) A fail has no note, and goes
  // where it landed.
  final measureOfUnits =
      noteSeconds == null ? units : (noteSeconds / secondsPerUnit).roundToDouble();
  final measureIndex = layout.indexAt(measureOfUnits);
  final offset = hit.offsetSeconds;
  return (
    measureIndex,
    StaffMark(
      units: units - layout.starts[measureIndex],
      color: judgementColor(hit.judgement),
      isAbsence: hit.hitTimeSeconds == null,
      // Just the signed number under the staff: a unit would crowd the
      // labels of closely spaced notes.
      label: withOffset && _showsDirection(hit) && offset != null
          ? offsetText(offset).replaceAll(' ms', '')
          : null,
    ),
  );
}
