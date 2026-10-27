import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import 'app_theme.dart';
import 'beam_groups.dart';

/// Renders one measure as real staff notation using the Bravura SMuFL font,
/// with noteheads always on the "C5" third space (the fixed-pitch convention
/// used for unpitched percussion). Every glyph is laid out with width
/// proportional to its duration, not idiomatic engraving spacing — this is
/// deliberate: it means a note's x-position and the playhead's x-position
/// (see [playheadUnits]) both come from the exact same time-to-position
/// formula, so alignment between the moving bar and the notes it should
/// coincide with is guaranteed by construction rather than approximated.
class StaffNotationView extends StatelessWidget {
  /// Drawn across the full width, scaled to its own time signature's
  /// capacity ([Measure.capacityUnits]).
  final Measure measure;

  /// Whether to print the measure's time signature after the clef -- as
  /// sheet music does at the start of a piece and wherever it changes.
  final bool showTimeSignature;

  /// Continuous position within this measure, in [RhythmGrid] units
  /// (0..the measure's capacity), or null to hide the playhead.
  final double? playheadUnits;

  /// Whether to show an insertion-point cursor at the end of the entered
  /// content (append-only entry — hidden during playback).
  final bool showCursor;

  /// Marks drawn in a row under the staff -- where the player's hits
  /// actually landed. Positioned by the same time-to-position formula as
  /// the notes, so a mark sits directly under its note only if the hit was
  /// on time. A new list must be passed for a change to be drawn.
  final List<StaffMark> marks;

  /// How tall to draw. Everything drawn fits from [minHeight] up; extra
  /// height is split evenly above and below.
  final double height;

  /// Which of [measure]'s events to highlight as selected, if any.
  final int? selectedEventIndex;

  /// Colours for individual events (by index into [measure]'s events),
  /// drawn instead of the ink colour -- e.g. each note in the colour of the
  /// judgement it got. Events not listed stay in ink. A new map must be
  /// passed for a change to be drawn.
  final Map<int, Color> eventColors;

  /// The parts of hairpins (crescendos, decrescendos) under this measure
  /// -- see [RhythmScore.hairpinSegmentsIn]. A note's dynamic marking comes
  /// with the note itself. A new list must be passed for a change to be
  /// drawn.
  final List<HairpinSegment> hairpins;

  /// Called when the staff is tapped: with the index of the event tapped,
  /// or null for a tap where there is none (e.g. the empty end of the
  /// measure). Without it, the staff doesn't respond to taps.
  final ValueChanged<int?>? onTapEvent;

  /// The SMuFL glyph for [mark], as written under the staff.
  static String dynamicGlyph(DynamicMark mark) => _StaffPainter._dynamicGlyphs[mark]!;

  static const double defaultHeight = 140;
  static const double minHeight = 112;

  const StaffNotationView({
    super.key,
    required this.measure,
    this.showTimeSignature = false,
    this.playheadUnits,
    this.showCursor = false,
    this.marks = const [],
    this.height = defaultHeight,
    this.selectedEventIndex,
    this.onTapEvent,
    this.eventColors = const {},
    this.hairpins = const [],
  }) : assert(height >= minHeight);

  /// Where, across a staff [width] wide, position [units] within [measure]
  /// is drawn -- the left edge of a note starting there. The one formula
  /// notes, the playhead, marks and taps all go by.
  static double xForUnits(
    Measure measure, {
    required bool showTimeSignature,
    required double width,
    required double units,
  }) {
    final contentLeft = _StaffPainter.contentLeftFor(measure, showTimeSignature);
    final contentWidth = width - contentLeft - _StaffPainter._rightPadding;
    return contentLeft + units / measure.capacityUnits * contentWidth;
  }

  /// Which event a tap at [dx] lands on: the one whose stretch of the staff
  /// contains it -- or null past the last event.
  int? _eventIndexAt(double dx, double width) {
    var start = 0;
    for (var index = 0; index < measure.events.length; index++) {
      final end = start + measure.events[index].durationUnits;
      // A note's stretch begins a little before its left edge, where its
      // notehead starts to read as "this note" to a finger.
      final left =
          xForUnits(
            measure,
            showTimeSignature: showTimeSignature,
            width: width,
            units: start.toDouble(),
          ) -
          _StaffPainter._tapSlop;
      final right =
          xForUnits(
            measure,
            showTimeSignature: showTimeSignature,
            width: width,
            units: end.toDouble(),
          ) -
          _StaffPainter._tapSlop;
      if (dx >= left && dx < right) return index;
      start = end;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final staff = CustomPaint(
      painter: _StaffPainter(
        palette: AppPalette.of(context),
        measure: measure,
        showTimeSignature: showTimeSignature,
        playheadUnits: playheadUnits,
        showCursor: showCursor,
        marks: marks,
        selectedEventIndex: selectedEventIndex,
        eventColors: eventColors,
        hairpins: hairpins,
      ),
    );
    final onTap = onTapEvent;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: onTap == null
          ? staff
          : LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    onTap(_eventIndexAt(details.localPosition.dx, constraints.maxWidth)),
                child: staff,
              ),
            ),
    );
  }
}

/// One mark under the staff of a [StaffNotationView].
class StaffMark {
  /// Position within the measure, in [RhythmGrid] units. May fall slightly
  /// outside the measure (a hit just early for its first note, or just late
  /// for its last), and is then drawn just past the corresponding end.
  final double units;

  final Color color;

  /// Drawn as a cross instead of a dot: something that should have happened
  /// here and didn't (a note nobody hit), rather than a hit.
  final bool isAbsence;

  /// A few characters printed small under the mark, e.g. a timing error.
  /// Needs the staff's full [StaffNotationView.defaultHeight] to fit.
  final String? label;

  const StaffMark({required this.units, required this.color, this.isAbsence = false, this.label});
}

class _StaffPainter extends CustomPainter {
  /// Ink for the staff and notes; the accent for the playhead and the
  /// picked note.
  final AppPalette palette;
  final Measure measure;
  final bool showTimeSignature;
  final double? playheadUnits;
  final bool showCursor;
  final List<StaffMark> marks;
  final int? selectedEventIndex;
  final Map<int, Color> eventColors;
  final List<HairpinSegment> hairpins;

  _StaffPainter({
    required this.palette,
    required this.measure,
    required this.showTimeSignature,
    this.playheadUnits,
    required this.showCursor,
    required this.marks,
    this.selectedEventIndex,
    this.eventColors = const {},
    this.hairpins = const [],
  });

  /// SMuFL's dynamic letters, as written under the staff.
  static const _dynamicGlyphs = {
    DynamicMark.pp: '\uE52B', // dynamicPP
    DynamicMark.p: '\uE520', // dynamicPiano
    DynamicMark.mp: '\uE52C', // dynamicMP
    DynamicMark.mf: '\uE52D', // dynamicMF
    DynamicMark.f: '\uE522', // dynamicForte
    DynamicMark.ff: '\uE52F', // dynamicFF
  };

  static const double _dynamicFontSize = _fontSize * 0.6;

  /// Where dynamics sit: just under the staff, above the row of hit marks.
  static const double _dynamicsBaseline = _lineSpacing * 1.45;
  static const double _hairpinMiddle = _lineSpacing * 1.1;
  static const double _hairpinOpening = _lineSpacing * 0.45;

  /// How far left of a note's drawn edge its tappable (and highlighted)
  /// stretch starts.
  static const double _tapSlop = 4;

  /// Where notes start being drawn: after the clef, and the time signature
  /// if shown.
  static double contentLeftFor(Measure measure, bool showTimeSignature) {
    var left = _leftPadding + _clefWidth;
    if (showTimeSignature) left += _timeSignatureWidth(measure.meter) + _timeSignatureGap;
    return left;
  }

  static const double _timeSignatureGap = 14;

  static const double _lineSpacing = 10;
  static const double _clefWidth = 44;
  static const double _leftPadding = 12;
  static const double _rightPadding = 12;
  static const double _fontSize = _lineSpacing * 4;

  // SMuFL codepoints, from the official w3c/smufl glyphnames.json reference.
  static const String _gClef = '';
  static const String _articAccentAbove = '';

  static const String _tuplet3 = '';

  static const String _articMarcatoAbove = '';

  /// The mark printed over a note of each type that has one.
  static const _articulationGlyphs = {
    EventType.accent: _articAccentAbove,
    EventType.marcato: _articMarcatoAbove,
  };

  // A flam's grace note: a small eighth note with a stroke through its stem.
  static const String _graceNoteSlashed = ''; // graceNoteAcciaccaturaStemUp

  /// How much smaller than a full note a drag's grace notes are drawn (the
  /// flam's glyph is made that small already).
  static const double _graceScale = 0.6;

  /// How far left of its note's edge a grace note's edge is, and how far
  /// apart a drag's two are.
  static const double _graceGap = _lineSpacing * 0.9;

  /// Approximate notehead width at [_fontSize], so a triplet bracket can
  /// reach the right edge of its last note rather than stopping at its left.
  static const double _noteheadWidth = _lineSpacing * 1.2;

  // A triplet eighth is drawn as an ordinary eighth; the "3" over its group
  // (see [_paintTripletMark]) is what marks it as a triplet.
  static const _noteGlyphs = {
    NoteValue.half: '', // noteHalfUp
    NoteValue.eighthTriplet: '', // note8thUp
    NoteValue.quarter: '', // noteQuarterUp
    NoteValue.eighth: '', // note8thUp
    NoteValue.sixteenth: '', // note16thUp
  };

  /// The plain note a triplet note is drawn as (the "3" over its group is
  /// what marks it): its own shape for anything else.
  static NoteValue _drawnAs(NoteValue value) {
    switch (value) {
      case NoteValue.quarterTriplet:
        return NoteValue.quarter;
      case NoteValue.eighthTriplet:
        return NoteValue.eighth;
      case NoteValue.sixteenthTriplet:
        return NoteValue.sixteenth;
      case NoteValue.half:
      case NoteValue.quarter:
      case NoteValue.eighth:
      case NoteValue.sixteenth:
        return value;
    }
  }

  /// A note under a beam is drawn as a notehead and stem only -- the quarter
  /// note's shape -- with the beam drawn over the stems in place of flags.
  static const String _beamedNoteGlyph = ''; // noteQuarterUp

  // The font's own measurements for that glyph, in staff spaces: where its
  // stem stands and how far it reaches above the middle of the notehead.
  static const double _stemRight = _lineSpacing * 1.18;
  static const double _stemThickness = _lineSpacing * 0.12;
  static const double _stemHeight = _lineSpacing * 3.5;

  static const double _beamThickness = _lineSpacing * 0.5;
  static const double _beamGap = _lineSpacing * 0.25;

  /// How long a sixteenth's second beam is when the note has no sixteenth
  /// beside it to reach across to.
  static const double _beamStubLength = _lineSpacing * 1.1;

  static const _restGlyphs = {
    NoteValue.half: '', // restHalf
    NoteValue.eighthTriplet: '', // rest8th
    NoteValue.quarter: '', // restQuarter
    NoteValue.eighth: '', // rest8th
    NoteValue.sixteenth: '', // rest16th
  };

  @override
  void paint(Canvas canvas, Size size) {
    // Everything drawn spans from about 8.1 staff spaces above the bottom
    // staff line (a triplet's "3"; half a space more over an accented,
    // beamed triplet) to about 2.7 below it (the marks under
    // the staff); centring that span, rather than the staff itself, is what
    // lets it fit in [StaffNotationView.minHeight].
    final staffBottom = size.height / 2 + _lineSpacing * 2.7;
    final middleLineY = staffBottom - 2 * _lineSpacing;
    final c5Y = staffBottom - 2.5 * _lineSpacing; // third space from bottom

    final linePaint = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = staffBottom - i * _lineSpacing;
      canvas.drawLine(Offset(_leftPadding, y), Offset(size.width - _rightPadding, y), linePaint);
    }

    _paintGlyph(canvas, _gClef, _leftPadding, staffBottom - _lineSpacing, _fontSize * 1.1);

    if (showTimeSignature) {
      _paintTimeSignature(canvas, measure.meter, _leftPadding + _clefWidth, staffBottom);
    }
    final unitsTotal = measure.capacityUnits.toDouble();

    double xForUnit(double unit) => StaffNotationView.xForUnits(
      measure,
      showTimeSignature: showTimeSignature,
      width: size.width,
      units: unit,
    );

    final selected = selectedEventIndex;
    if (selected != null && selected < measure.events.length) {
      final start = measure.events
          .take(selected)
          .fold<int>(0, (sum, event) => sum + event.durationUnits);
      final end = start + measure.events[selected].durationUnits;
      canvas.drawRRect(
        RRect.fromLTRBR(
          xForUnit(start.toDouble()) - _tapSlop,
          staffBottom - 7 * _lineSpacing,
          xForUnit(end.toDouble()) - _tapSlop,
          staffBottom + 1.5 * _lineSpacing,
          const Radius.circular(6),
        ),
        Paint()..color = palette.accent.withValues(alpha: 0.16),
      );
    }

    // X-positions of the triplet group currently being collected: consecutive
    // triplet events of one length, marked with a "3" once three are in (or
    // once the run is broken off early by a different note value or the end
    // of the measure).
    final tripletGroupXs = <double>[];
    NoteValue? tripletGroupValue;
    // Whether a note of that group has an accent above its beam, which the
    // "3" then has to clear.
    var tripletGroupHasBeamedAccent = false;
    void markTripletGroup() {
      if (tripletGroupXs.isEmpty) return;
      _paintTripletMark(
        canvas,
        tripletGroupXs.first,
        tripletGroupXs.last + _noteheadWidth,
        staffBottom - (tripletGroupHasBeamedAccent ? 8 : 7.5) * _lineSpacing,
      );
      tripletGroupXs.clear();
      tripletGroupHasBeamedAccent = false;
    }

    final groups = beamGroups(measure);
    final beamedEvents = {
      for (final group in groups)
        for (final note in group) note.eventIndex,
    };

    var cursorUnit = 0;
    for (final (eventIndex, event) in measure.events.indexed) {
      final x = xForUnit(cursorUnit.toDouble());
      if (event.value.isTriplet) {
        if (event.value != tripletGroupValue) markTripletGroup();
        tripletGroupValue = event.value;
        tripletGroupXs.add(x);
        if (_articulationGlyphs.containsKey(event.type) && beamedEvents.contains(eventIndex)) {
          tripletGroupHasBeamedAccent = true;
        }
        if (tripletGroupXs.length == 3) markTripletGroup();
      } else {
        markTripletGroup();
      }
      final color = eventColors[eventIndex] ?? _ink;
      if (event.isRest) {
        _paintGlyph(
          canvas,
          _restGlyphs[_drawnAs(event.value)]!,
          x,
          middleLineY,
          _fontSize,
          color: color,
        );
      } else {
        final beamed = beamedEvents.contains(eventIndex);
        _paintGlyph(
          canvas,
          beamed ? _beamedNoteGlyph : _noteGlyphs[_drawnAs(event.value)]!,
          x,
          c5Y,
          _fontSize,
          color: color,
        );
        _paintGraceNotes(canvas, event.ornament.graceNoteCount, x, c5Y, color);
        if (event.ornament == Ornament.roll) {
          // Slashes and beams (or flags) add up to three, as printed music
          // writes a roll: three on a quarter, two on an eighth, one on a
          // sixteenth.
          _paintRollSlashes(canvas, 3 - beamCount(event.value), x, c5Y, color);
        }
        final articulation = _articulationGlyphs[event.type];
        if (articulation != null) {
          // Beside the stem, where a flagged note has room for it; a beam
          // runs through there, so under one the accent goes above the beam.
          _paintGlyph(
            canvas,
            articulation,
            x,
            beamed ? c5Y - _stemHeight - _lineSpacing * 0.2 : c5Y - _lineSpacing * 2.5,
            _fontSize * 0.7,
            color: color,
          );
        }
      }
      cursorUnit += event.durationUnits;
    }
    markTripletGroup();

    for (final group in groups) {
      _paintBeams(
        canvas,
        [for (final note in group) xForUnit(note.startUnits.toDouble())],
        [for (final note in group) note.beams],
        [for (final note in group) eventColors[note.eventIndex] ?? _ink],
        c5Y - _stemHeight,
      );
    }

    _paintDynamics(canvas, staffBottom, xForUnit);

    // Shifted half a notehead right of the time-to-position formula, which
    // gives a note's left edge: an on-time hit then sits centered under its
    // notehead instead of under its edge.
    final markY = staffBottom + 2.2 * _lineSpacing;
    for (final mark in marks) {
      final center = Offset(xForUnit(mark.units) + _noteheadWidth / 2, markY);
      if (mark.isAbsence) {
        const arm = 4.0;
        final crossPaint = Paint()
          ..color = mark.color
          ..strokeWidth = 2;
        canvas.drawLine(
          center + const Offset(-arm, -arm),
          center + const Offset(arm, arm),
          crossPaint,
        );
        canvas.drawLine(
          center + const Offset(-arm, arm),
          center + const Offset(arm, -arm),
          crossPaint,
        );
      } else {
        canvas.drawCircle(center, 4.5, Paint()..color = mark.color);
      }
      final label = mark.label;
      if (label != null) {
        final text = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 9, color: mark.color, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(center.dx - text.width / 2, center.dy + 6));
      }
    }

    if (showCursor && cursorUnit < unitsTotal) {
      final x = xForUnit(cursorUnit.toDouble());
      canvas.drawLine(
        Offset(x, staffBottom + _lineSpacing),
        Offset(x, staffBottom - 5 * _lineSpacing),
        Paint()
          ..color = palette.mutedInk
          ..strokeWidth = 2,
      );
    }

    if (playheadUnits != null) {
      final x = xForUnit(playheadUnits!.clamp(0, unitsTotal));
      canvas.drawLine(
        Offset(x, staffBottom + _lineSpacing),
        Offset(x, staffBottom - 5 * _lineSpacing),
        Paint()
          ..color = palette.accent
          ..strokeWidth = 3,
      );
    }
  }

  /// Draws each note's dynamic marking under it, and the hairpins.
  void _paintDynamics(Canvas canvas, double staffBottom, double Function(double) xForUnit) {
    final markedAt = <int, double>{}; // start unit -> width of the marking there
    var unit = 0;
    for (final (eventIndex, event) in measure.events.indexed) {
      final mark = event.dynamicMark;
      if (mark != null) {
        final glyph = _dynamicGlyphs[mark]!;
        _paintGlyph(
          canvas,
          glyph,
          xForUnit(unit.toDouble()),
          staffBottom + _dynamicsBaseline,
          _dynamicFontSize,
          color: eventColors[eventIndex] ?? _ink,
        );
        markedAt[unit] = _cachedGlyphPainter(glyph, _dynamicFontSize).width;
      }
      unit += event.durationUnits;
    }

    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final middle = staffBottom + _hairpinMiddle;
    for (final segment in hairpins) {
      var left = xForUnit(segment.startUnits);
      // Clear of a marking written at the note it starts from ("p <").
      final markWidth = segment.startFraction == 0 ? markedAt[segment.startUnits.round()] : null;
      if (markWidth != null) left += markWidth + 4;
      final right = xForUnit(segment.endUnits) - 2;
      if (right - left < 4) continue;
      // A crescendo opens from nothing to full; a decrescendo closes.
      double opening(double fraction) =>
          _hairpinOpening *
          (segment.kind == Hairpin.crescendo ? fraction : 1 - fraction);
      final openLeft = opening(segment.startFraction);
      final openRight = opening(segment.endFraction);
      canvas.drawPath(
        Path()
          ..moveTo(right, middle - openRight)
          ..lineTo(left, middle - openLeft)
          ..moveTo(right, middle + openRight)
          ..lineTo(left, middle + openLeft),
        paint,
      );
    }
  }

  // Laying out a glyph (font shaping) is expensive; there are only a handful
  // of distinct (glyph, fontSize) combinations in this whole widget, so
  // caching them means playback's every-frame repaint (needed for a smoothly
  // moving playhead) never redoes that work -- it only ever happens once per
  // combination, not once per glyph per frame. Without this, a measure with
  // several notes visibly stutters during playback while an empty measure
  // (no glyphs to lay out) stays smooth.
  static final Map<String, TextPainter> _glyphCache = {};

  Color get _ink => palette.ink;

  /// The colour glyphs are laid out in when only their size is wanted: the
  /// size is the same in any colour.
  static const Color _measuringColor = Colors.black;

  static TextPainter _cachedGlyphPainter(
    String glyph,
    double fontSize, {
    Color color = _measuringColor,
  }) {
    final key = '$glyph@$fontSize@${color.toARGB32()}';
    return _glyphCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(fontFamily: 'Bravura', fontSize: fontSize, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  void _paintGlyph(
    Canvas canvas,
    String glyph,
    double x,
    double baselineY,
    double fontSize, {
    Color? color,
  }) {
    final textPainter = _cachedGlyphPainter(glyph, fontSize, color: color ?? _ink);
    final baselineOffset = textPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    textPainter.paint(canvas, Offset(x, baselineY - baselineOffset));
  }

  /// Draws a roll's [count] slashes across the stem of the note whose left
  /// edge is at [noteX], stacked upward from just above its notehead (below
  /// where beams and flags are).
  void _paintRollSlashes(Canvas canvas, int count, double noteX, double c5Y, Color color) {
    const halfWidth = _lineSpacing * 0.55;
    const rise = _lineSpacing * 0.3;
    const thickness = _lineSpacing * 0.28;
    final stemX = noteX + _stemRight - _stemThickness / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final y = c5Y - _lineSpacing * (1.15 + 0.5 * i);
      canvas.drawPath(
        Path()
          ..moveTo(stemX - halfWidth, y + rise / 2)
          ..lineTo(stemX + halfWidth, y - rise / 2)
          ..lineTo(stemX + halfWidth, y - rise / 2 + thickness)
          ..lineTo(stemX - halfWidth, y + rise / 2 + thickness)
          ..close(),
        paint,
      );
    }
  }

  /// Draws the [count] grace notes of a flam (1) or drag (2) just left of
  /// the note whose left edge is at [noteX], on the same line as it, with a
  /// slur joining them to it. They take no time, so unlike everything else
  /// they aren't placed by the time-to-position formula: they sit in the
  /// space before their note.
  void _paintGraceNotes(Canvas canvas, int count, double noteX, double c5Y, Color color) {
    if (count == 0) return;
    final firstX = noteX - count * _graceGap - _lineSpacing * 0.2;
    if (count == 1) {
      _paintGlyph(canvas, _graceNoteSlashed, firstX, c5Y, _fontSize, color: color);
    } else {
      // Two small notes under a double beam, drawn as beamed notes are.
      const stemRight = _stemRight * _graceScale;
      const stemThickness = _stemThickness * _graceScale;
      const beamThickness = _beamThickness * _graceScale;
      final top = c5Y - _stemHeight * _graceScale;
      final paint = Paint()..color = color;
      for (var i = 0; i < count; i++) {
        _paintGlyph(
          canvas,
          _beamedNoteGlyph,
          firstX + i * _graceGap,
          c5Y,
          _fontSize * _graceScale,
          color: color,
        );
      }
      for (var beam = 0; beam < 2; beam++) {
        final y = top + beam * (beamThickness + _beamGap * _graceScale);
        canvas.drawRect(
          Rect.fromLTRB(
            firstX + stemRight - stemThickness,
            y,
            firstX + (count - 1) * _graceGap + stemRight,
            y + beamThickness,
          ),
          paint,
        );
      }
    }

    // The slur, under the noteheads from the first grace note to the note.
    final start = Offset(firstX + _noteheadWidth * _graceScale / 2, c5Y + _lineSpacing * 0.55);
    final end = Offset(noteX + _noteheadWidth / 2, c5Y + _lineSpacing * 0.75);
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo((start.dx + end.dx) / 2, end.dy + _lineSpacing * 0.7, end.dx, end.dy),
      Paint()
        ..color = color
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  /// Draws [meter]'s two numbers stacked in the staff, starting at [left],
  /// and returns how wide they are. SMuFL's time-signature digits
  /// (`timeSig0`..`timeSig9`, U+E080..U+E089) are drawn centred on their
  /// baseline, so each number's baseline goes in the middle of its half of
  /// the staff.
  static String _timeSignatureDigits(int number) =>
      String.fromCharCodes(number.toString().codeUnits.map((digit) => 0xE080 + digit - 0x30));

  static double _timeSignatureWidth(TimeSignature meter) {
    final topWidth = _cachedGlyphPainter(_timeSignatureDigits(meter.beats), _fontSize).width;
    final bottomWidth = _cachedGlyphPainter(_timeSignatureDigits(meter.beatUnit), _fontSize).width;
    return topWidth > bottomWidth ? topWidth : bottomWidth;
  }

  double _paintTimeSignature(Canvas canvas, TimeSignature meter, double left, double staffBottom) {
    final top = _timeSignatureDigits(meter.beats);
    final bottom = _timeSignatureDigits(meter.beatUnit);
    final topWidth = _cachedGlyphPainter(top, _fontSize).width;
    final bottomWidth = _cachedGlyphPainter(bottom, _fontSize).width;
    final width = _timeSignatureWidth(meter);
    _paintGlyph(
      canvas,
      top,
      left + (width - topWidth) / 2,
      staffBottom - 3 * _lineSpacing,
      _fontSize,
    );
    _paintGlyph(
      canvas,
      bottom,
      left + (width - bottomWidth) / 2,
      staffBottom - _lineSpacing,
      _fontSize,
    );
    return width;
  }

  /// Draws the beams of one group of notes whose left edges are at [noteXs]:
  /// one beam across all of them at [top] (the top of their stems), and a
  /// second one under it wherever [beamCounts] says 2 -- across sixteenths
  /// next to each other, or as a short stub on a sixteenth with none beside
  /// it. Each note's half of a beam is in that note's colour ([colors]), so
  /// a note coloured by its judgement is coloured all the way up.
  void _paintBeams(
    Canvas canvas,
    List<double> noteXs,
    List<int> beamCounts,
    List<Color> colors,
    double top,
  ) {
    double stemLeft(int i) => noteXs[i] + _stemRight - _stemThickness;
    double stemRight(int i) => noteXs[i] + _stemRight;

    // A beam from note [first] to note [last], changing colour halfway
    // between each two notes.
    void span(int first, int last, double y) {
      for (var i = first; i <= last; i++) {
        final left = i == first ? stemLeft(i) : (stemRight(i - 1) + stemLeft(i)) / 2;
        final right = i == last ? stemRight(i) : (stemRight(i) + stemLeft(i + 1)) / 2;
        canvas.drawRect(
          Rect.fromLTRB(left, y, right, y + _beamThickness),
          Paint()..color = colors[i],
        );
      }
    }

    final last = noteXs.length - 1;
    span(0, last, top);

    final secondY = top + _beamThickness + _beamGap;
    var i = 0;
    while (i <= last) {
      if (beamCounts[i] < 2) {
        i++;
        continue;
      }
      var runEnd = i;
      while (runEnd < last && beamCounts[runEnd + 1] >= 2) {
        runEnd++;
      }
      if (runEnd > i) {
        span(i, runEnd, secondY);
      } else {
        // Toward the note before it, or -- for the first note of the group
        // -- toward the one after; never more than halfway there.
        final pointsRight = i == 0;
        final neighbour = pointsRight ? stemLeft(i + 1) : stemRight(i - 1);
        final reach = pointsRight ? neighbour - stemRight(i) : stemLeft(i) - neighbour;
        final length = reach / 2 < _beamStubLength ? reach / 2 : _beamStubLength;
        canvas.drawRect(
          pointsRight
              ? Rect.fromLTRB(stemLeft(i), secondY, stemRight(i) + length, secondY + _beamThickness)
              : Rect.fromLTRB(
                  stemLeft(i) - length,
                  secondY,
                  stemRight(i),
                  secondY + _beamThickness,
                ),
          Paint()..color = colors[i],
        );
      }
      i = runEnd + 1;
    }
  }

  /// Draws a triplet's "3" centered over [left]..[right] at height [y], with
  /// a bracket out to both ends when the span is wide enough to hold one
  /// (a lone triplet note gets just the numeral).
  void _paintTripletMark(Canvas canvas, double left, double right, double y) {
    const fontSize = _fontSize * 0.6;
    const hookHeight = _lineSpacing * 0.5;
    const numeralGap = 3.0;

    final numeralWidth = _cachedGlyphPainter(_tuplet3, fontSize).width;
    final center = (left + right) / 2;
    final numeralLeft = center - numeralWidth / 2;
    _paintGlyph(canvas, _tuplet3, numeralLeft, y + hookHeight, fontSize);

    final bracketInnerLeft = numeralLeft - numeralGap;
    final bracketInnerRight = numeralLeft + numeralWidth + numeralGap;
    if (bracketInnerLeft <= left || bracketInnerRight >= right) return;

    final bracketPaint = Paint()
      ..color = _ink
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(left, y + hookHeight)
        ..lineTo(left, y)
        ..lineTo(bracketInnerLeft, y)
        ..moveTo(bracketInnerRight, y)
        ..lineTo(right, y)
        ..lineTo(right, y + hookHeight),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_StaffPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.measure != measure ||
      oldDelegate.showTimeSignature != showTimeSignature ||
      oldDelegate.playheadUnits != playheadUnits ||
      oldDelegate.showCursor != showCursor ||
      oldDelegate.marks != marks ||
      oldDelegate.selectedEventIndex != selectedEventIndex ||
      oldDelegate.eventColors != eventColors ||
      oldDelegate.hairpins != hairpins;
}
