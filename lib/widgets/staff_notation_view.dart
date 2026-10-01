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
  final Measure measure;

  /// This measure's capacity in [RhythmGrid] units (see
  /// [RhythmScore.unitsPerMeasure]), used to scale note/playhead
  /// x-positions. Defaults to 4/4 for callers without a specific score's
  /// meter in hand.
  final int unitsPerMeasure;

  /// Continuous position within this measure, in [RhythmGrid] units
  /// (0..[unitsPerMeasure]), or null to hide the playhead.
  final double? playheadUnits;

  /// Whether to show an insertion-point cursor at the end of the entered
  /// content (append-only entry — hidden during playback).
  final bool showCursor;

  const StaffNotationView({
    super.key,
    required this.measure,
    this.unitsPerMeasure = RhythmGrid.defaultUnitsPerMeasure,
    this.playheadUnits,
    this.showCursor = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _StaffPainter(
          measure: measure,
          unitsPerMeasure: unitsPerMeasure,
          playheadUnits: playheadUnits,
          showCursor: showCursor,
        ),
      ),
    );
  }
}

class _StaffPainter extends CustomPainter {
  final Measure measure;
  final int unitsPerMeasure;
  final double? playheadUnits;
  final bool showCursor;

  _StaffPainter({
    required this.measure,
    required this.unitsPerMeasure,
    this.playheadUnits,
    required this.showCursor,
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
    final staffBottom = size.height / 2 + _lineSpacing * 2;
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

    final contentLeft = _leftPadding + _clefWidth;
    final contentWidth = size.width - contentLeft - _rightPadding;
    final unitsTotal = unitsPerMeasure.toDouble();

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
      oldDelegate.unitsPerMeasure != unitsPerMeasure ||
      oldDelegate.playheadUnits != playheadUnits ||
      oldDelegate.showCursor != showCursor;
}
