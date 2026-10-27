import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';

/// A tempo written as sheet music writes it: the note one beat is, then
/// "= 130" -- so whoever reads it knows which note to count (or tap) at
/// that speed.
class TempoMark extends StatelessWidget {
  final TempoBeat beat;
  final int bpm;

  /// For the "= 130"; the note is drawn to match its size.
  final TextStyle? style;

  const TempoMark({super.key, required this.beat, required this.bpm, this.style});

  /// The note glyph for [beat]: SMuFL's metronome-mark notes, which are made
  /// to sit in a line of text.
  static String glyph(TempoBeat beat) {
    switch (beat) {
      case TempoBeat.eighth:
        return ''; // metNote8thUp
      case TempoBeat.quarter:
        return ''; // metNoteQuarterUp
      case TempoBeat.dottedQuarter:
        return ''; // metNoteQuarterUp, metAugmentationDot
      case TempoBeat.half:
        return ''; // metNoteHalfUp
    }
  }

  /// [beat]'s name, for screen readers and menus: "quarter note".
  static String noteName(TempoBeat beat) {
    switch (beat) {
      case TempoBeat.eighth:
        return 'eighth note';
      case TempoBeat.quarter:
        return 'quarter note';
      case TempoBeat.dottedQuarter:
        return 'dotted quarter note';
      case TempoBeat.half:
        return 'half note';
    }
  }

  /// The note on its own, sized for text of [fontSize], sitting on the
  /// text's baseline.
  static TextSpan noteSpan(TempoBeat beat, double fontSize, {Color? color}) => TextSpan(
    text: glyph(beat),
    style: TextStyle(
      fontFamily: 'Bravura',
      fontSize: fontSize * 1.25,
      color: color,
      // Bravura's line metrics are made for whole staves; without this the
      // note would make the line several times taller than its text.
      height: 1,
      // The dot would otherwise touch the notehead.
      letterSpacing: beat == TempoBeat.dottedQuarter ? fontSize * 0.15 : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style.merge(style);
    return Semantics(
      label:
          '$bpm beats a minute, one beat ${beat == TempoBeat.eighth ? 'an' : 'a'} ${noteName(beat)}',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            noteSpan(beat, textStyle.fontSize ?? 14, color: textStyle.color),
            TextSpan(text: ' = $bpm', style: style),
          ],
        ),
      ),
    );
  }
}
