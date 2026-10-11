import '../models/rhythm_score.dart';

/// How full [measure] is, in its own beats -- e.g. "2½ of 4 beats filled"
/// -- rather than in the app's internal grid units, which mean nothing to a
/// musician. A part-filled beat is shown as a fraction: halves, thirds and
/// quarters (sixteenths and triplets) get their own fraction characters;
/// rarer mixes (a sixteenth plus a triplet eighth, say) are written out,
/// e.g. "1 7/12".
String filledBeatsText(Measure measure) {
  final unitsPerBeat = measure.meter.unitsPerBeat;
  final beats = measure.meter.beats;
  return '${_beatsAmount(measure.filledUnits, unitsPerBeat)} of $beats '
      '${beats == 1 ? 'beat' : 'beats'} filled';
}

String _beatsAmount(int units, int unitsPerBeat) {
  final whole = units ~/ unitsPerBeat;
  final remainder = units % unitsPerBeat;
  if (remainder == 0) return '$whole';
  final divisor = remainder.gcd(unitsPerBeat);
  final numerator = remainder ~/ divisor;
  final denominator = unitsPerBeat ~/ divisor;
  final glyph = _fractionGlyphs[(numerator, denominator)];
  final fraction = glyph ?? '$numerator/$denominator';
  if (whole == 0) return fraction;
  return glyph != null ? '$whole$fraction' : '$whole $fraction';
}

const _fractionGlyphs = {
  (1, 2): '½',
  (1, 3): '⅓',
  (2, 3): '⅔',
  (1, 4): '¼',
  (3, 4): '¾',
  (1, 6): '⅙',
  (5, 6): '⅚',
  (1, 8): '⅛',
  (3, 8): '⅜',
  (5, 8): '⅝',
  (7, 8): '⅞',
};
