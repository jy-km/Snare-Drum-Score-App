/// Works out a tempo from taps: tap along with the beat you have in mind,
/// and the tempo is how often you tapped -- from the second tap on, the
/// average over the last few, so it settles as you keep going.
///
/// Stopping for a while starts afresh, and so does a tap clearly faster or
/// slower than the ones before it (the player changed their mind), keeping
/// only the latest gap.
class TapTempo {
  final int minBpm;
  final int maxBpm;

  TapTempo({required this.minBpm, required this.maxBpm});

  /// How many of the latest taps the tempo is averaged over.
  static const int tapsAveraged = 5;

  /// A gap longer than this starts a new tempo -- just longer than the gap
  /// between beats at the slowest tempo the app allows (3s at 20 BPM).
  static const Duration resetAfter = Duration(milliseconds: 3500);

  /// How far a gap may stray from the average so far before it's taken
  /// for a new tempo rather than unsteady tapping.
  static const double changeOfMind = 0.4;

  final _taps = <DateTime>[];

  /// Notes a tap at [now] and returns the tempo the taps so far make, in
  /// beats per minute -- or null after the first tap, which has no gap yet.
  int? tap(DateTime now) {
    if (_taps.isNotEmpty && now.difference(_taps.last) > resetAfter) _taps.clear();
    if (_taps.length >= 2) {
      final average = _averageGapSeconds;
      final gap = _secondsBetween(_taps.last, now);
      if ((gap - average).abs() > average * changeOfMind) _taps.removeRange(0, _taps.length - 1);
    }
    _taps.add(now);
    if (_taps.length > tapsAveraged) _taps.removeAt(0);
    if (_taps.length < 2) return null;
    return (60 / _averageGapSeconds).round().clamp(minBpm, maxBpm);
  }

  double get _averageGapSeconds => _secondsBetween(_taps.first, _taps.last) / (_taps.length - 1);

  static double _secondsBetween(DateTime a, DateTime b) =>
      b.difference(a).inMicroseconds / Duration.microsecondsPerSecond;
}
