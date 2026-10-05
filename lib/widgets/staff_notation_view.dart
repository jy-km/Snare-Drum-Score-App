import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';

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
  }) : assert(height >= minHeight);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _StaffPainter(
          measure: measure,
          showTimeSignature: showTimeSignature,
          playheadUnits: playheadUnits,
          showCursor: showCursor,
          marks: marks,
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

  const StaffMark({
    required this.units,
    required this.color,
    this.isAbsence = false,
    this.label,
  });
}

class _StaffPainter extends CustomPainter {
  final Measure measure;
  final bool showTimeSignature;
  final double? playheadUnits;
  final bool showCursor;
  final List<StaffMark> marks;

  _StaffPainter({
    required this.measure,
    required this.showTimeSignature,
    this.playheadUnits,
    required this.showCursor,
    required this.marks,
  });

  static const double _lineSpacing = 10;
  static const double _clefWidth = 44;
  static const double _leftPadding = 12;
  static const double _rightPadding = 12;
  static const double _fontSize = _lineSpacing * 4;

  // SMuFL codepoints, from the official w3c/smufl glyphnames.json reference.
  static const String _gClef = '';
  static const String _articAccentAbove = '';

  static const String _tuplet3 = '';

  /// Approximate notehead width at [_fontSize], so a triplet bracket can
  /// reach the right edge of its last note rather than stopping at its left.
  static const double _noteheadWidth = _lineSpacing * 1.2;

  // A triplet eighth is drawn as an ordinary eighth; the "3" over its group
  // (see [_paintTripletMark]) is what marks it as a triplet.
  static const _noteGlyphs = {
    NoteValue.eighthTriplet: '', // note8thUp
    NoteValue.quarter: '', // noteQuarterUp
    NoteValue.eighth: '', // note8thUp
    NoteValue.sixteenth: '', // note16thUp
  };

  static const _restGlyphs = {
    NoteValue.eighthTriplet: '', // rest8th
    NoteValue.quarter: '', // restQuarter
    NoteValue.eighth: '', // rest8th
    NoteValue.sixteenth: '', // rest16th
  };

  @override
  void paint(Canvas canvas, Size size) {
    // Everything drawn spans from about 8.1 staff spaces above the bottom
    // staff line (a triplet's "3") to about 2.7 below it (the marks under
    // the staff); centring that span, rather than the staff itself, is what
    // lets it fit in [StaffNotationView.minHeight].
    final staffBottom = size.height / 2 + _lineSpacing * 2.7;
    final middleLineY = staffBottom - 2 * _lineSpacing;
    final c5Y = staffBottom - 2.5 * _lineSpacing; // third space from bottom

    final linePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = staffBottom - i * _lineSpacing;
      canvas.drawLine(Offset(_leftPadding, y), Offset(size.width - _rightPadding, y), linePaint);
    }

    _paintGlyph(canvas, _gClef, _leftPadding, staffBottom - _lineSpacing, _fontSize * 1.1);

    var contentLeft = _leftPadding + _clefWidth;
    if (showTimeSignature) {
      contentLeft += _paintTimeSignature(canvas, measure.meter, contentLeft, staffBottom) + 14;
    }
    final contentWidth = size.width - contentLeft - _rightPadding;
    final unitsTotal = measure.capacityUnits.toDouble();

    double xForUnit(double unit) => contentLeft + (unit / unitsTotal) * contentWidth;

    // X-positions of the triplet group currently being collected: consecutive
    // triplet events, marked with a "3" once three are in (or once the run
    // is broken off early by a different note value or the end of the
    // measure).
    final tripletGroupXs = <double>[];
    void markTripletGroup() {
      if (tripletGroupXs.isEmpty) return;
      _paintTripletMark(
        canvas,
        tripletGroupXs.first,
        tripletGroupXs.last + _noteheadWidth,
        staffBottom - 7.5 * _lineSpacing,
      );
      tripletGroupXs.clear();
    }

    var cursorUnit = 0;
    for (final event in measure.events) {
      final x = xForUnit(cursorUnit.toDouble());
      if (event.value == NoteValue.eighthTriplet) {
        tripletGroupXs.add(x);
        if (tripletGroupXs.length == 3) markTripletGroup();
      } else {
        markTripletGroup();
      }
      if (event.isRest) {
        _paintGlyph(canvas, _restGlyphs[event.value]!, x, middleLineY, _fontSize);
      } else {
        _paintGlyph(canvas, _noteGlyphs[event.value]!, x, c5Y, _fontSize);
        if (event.type == EventType.accent) {
          _paintGlyph(
            canvas,
            _articAccentAbove,
            x,
            c5Y - _lineSpacing * 2.5,
            _fontSize * 0.7,
          );
        }
      }
      cursorUnit += event.durationUnits;
    }
    markTripletGroup();

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
        canvas.drawLine(center + const Offset(-arm, -arm), center + const Offset(arm, arm), crossPaint);
        canvas.drawLine(center + const Offset(-arm, arm), center + const Offset(arm, -arm), crossPaint);
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
          ..color = Colors.blue.withValues(alpha: 0.5)
          ..strokeWidth = 2,
      );
    }

    if (playheadUnits != null) {
      final x = xForUnit(playheadUnits!.clamp(0, unitsTotal));
      canvas.drawLine(
        Offset(x, staffBottom + _lineSpacing),
        Offset(x, staffBottom - 5 * _lineSpacing),
        Paint()
          ..color = Colors.orange
          ..strokeWidth = 3,
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

  TextPainter _cachedGlyphPainter(String glyph, double fontSize) {
    final key = '$glyph@$fontSize';
    return _glyphCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(fontFamily: 'Bravura', fontSize: fontSize, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  void _paintGlyph(Canvas canvas, String glyph, double x, double baselineY, double fontSize) {
    final textPainter = _cachedGlyphPainter(glyph, fontSize);
    final baselineOffset = textPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    textPainter.paint(canvas, Offset(x, baselineY - baselineOffset));
  }

  /// Draws [meter]'s two numbers stacked in the staff, starting at [left],
  /// and returns how wide they are. SMuFL's time-signature digits
  /// (`timeSig0`..`timeSig9`, U+E080..U+E089) are drawn centred on their
  /// baseline, so each number's baseline goes in the middle of its half of
  /// the staff.
  double _paintTimeSignature(Canvas canvas, TimeSignature meter, double left, double staffBottom) {
    String digits(int number) =>
        String.fromCharCodes(number.toString().codeUnits.map((digit) => 0xE080 + digit - 0x30));
    final top = digits(meter.beats);
    final bottom = digits(meter.beatUnit);
    final topWidth = _cachedGlyphPainter(top, _fontSize).width;
    final bottomWidth = _cachedGlyphPainter(bottom, _fontSize).width;
    final width = topWidth > bottomWidth ? topWidth : bottomWidth;
    _paintGlyph(canvas, top, left + (width - topWidth) / 2, staffBottom - 3 * _lineSpacing, _fontSize);
    _paintGlyph(
        canvas, bottom, left + (width - bottomWidth) / 2, staffBottom - _lineSpacing, _fontSize);
    return width;
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
      ..color = Colors.black87
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
      oldDelegate.measure != measure ||
      oldDelegate.showTimeSignature != showTimeSignature ||
      oldDelegate.playheadUnits != playheadUnits ||
      oldDelegate.showCursor != showCursor ||
      oldDelegate.marks != marks;
}
