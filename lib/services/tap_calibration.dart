import 'dart:math' as math;

enum CalibrationFailure {
  /// Not enough hits landed consistently to average.
  tooFewHits,

  /// Hits were heard, but too scattered around the beat to trust an average.
  unsteady,
}

/// What a calibration run measured.
class CalibrationOutcome {
  /// How long after the app's clock says a beat happens the player's hit on
  /// that beat is heard, averaged over the run -- null if the run failed.
  final double? offsetSeconds;

  /// How many hits the average was taken over.
  final int hitCount;

  /// How far those hits typically strayed from the average (standard
  /// deviation).
  final double spreadSeconds;

  final CalibrationFailure? failure;

  const CalibrationOutcome._({
    this.offsetSeconds,
    required this.hitCount,
    required this.spreadSeconds,
    this.failure,
  });

  bool get succeeded => failure == null;
}

/// Works out the input offset from a calibration run: the player plays along
/// with a steady beat, and the offset is the average distance from each beat
/// (where the app's clock puts it) to the hit heard for it.
///
/// That distance is everything standing between the app's clock and a hit
/// arriving at the microphone -- the time sound takes to leave the phone and
/// reach the player's ears (large with Bluetooth headphones), plus the
/// microphone's own delay. Knowing it lets a practice run place hits on the
/// timeline without having to hear its own count-in.
class TapCalibration {
  /// Fewer consistent hits than this is too few to average.
  static const int minHits = 8;

  /// Hits further than this from the bulk of the others are left out of the
  /// average -- a stray sound, or one fumbled beat.
  static const double _outlierSeconds = 0.08;

  /// A larger spread than this among the hits kept means the player wasn't
  /// locked to the beat (or two different things were being heard), so the
  /// average wouldn't mean much.
  static const double _maxSpreadSeconds = 0.04;

  /// Offsets are reported from this far *before* the beat to just under one
  /// beat later. Which beat a hit belongs to can't be known from the hit
  /// alone, so an offset is only determined within one beat's length; real
  /// delays are essentially never negative (sound can't arrive before it is
  /// sent, though a player may anticipate slightly), so nearly all of that
  /// range is spent on the late side.
  static const double _earliestOffsetSeconds = -0.1;

  /// [hitTimes] are when each hit was heard, in seconds from the moment the
  /// app's clock says the first beat played; beats then fall every
  /// [beatSeconds]. Only hits from [fromSeconds] on are used, so the player
  /// has a few beats to settle in first.
  static CalibrationOutcome measure({
    required List<double> hitTimes,
    required double beatSeconds,
    double fromSeconds = 0,
  }) {
    // Each hit's position within its beat, as an angle: averaging angles
    // handles hits that straddle the wrap-around (e.g. just before and just
    // after a beat) which a plain average of remainders would get badly
    // wrong.
    final phases = [
      for (final time in hitTimes)
        if (time >= fromSeconds) 2 * math.pi * (time % beatSeconds) / beatSeconds,
    ];
    if (phases.length < minHits) {
      return CalibrationOutcome._(
        hitCount: phases.length,
        spreadSeconds: 0,
        failure: CalibrationFailure.tooFewHits,
      );
    }

    double secondsBetween(double phase, double center) {
      var difference = (phase - center) % (2 * math.pi);
      if (difference > math.pi) difference -= 2 * math.pi;
      return difference / (2 * math.pi) * beatSeconds;
    }

    // Average, drop what sits far from the average, and average again --
    // twice, since the first average is itself pulled off by the strays.
    var kept = phases;
    var center = _circularMean(kept);
    for (var round = 0; round < 2; round++) {
      kept = [
        for (final phase in phases)
          if (secondsBetween(phase, center).abs() <= _outlierSeconds) phase,
      ];
      if (kept.length < minHits) {
        return CalibrationOutcome._(
          hitCount: kept.length,
          spreadSeconds: 0,
          failure: CalibrationFailure.unsteady,
        );
      }
      center = _circularMean(kept);
    }

    var squaredSum = 0.0;
    for (final phase in kept) {
      final distance = secondsBetween(phase, center);
      squaredSum += distance * distance;
    }
    final spread = math.sqrt(squaredSum / kept.length);

    var offset = (center % (2 * math.pi)) / (2 * math.pi) * beatSeconds;
    if (offset >= beatSeconds + _earliestOffsetSeconds) offset -= beatSeconds;

    return CalibrationOutcome._(
      offsetSeconds: spread <= _maxSpreadSeconds ? offset : null,
      hitCount: kept.length,
      spreadSeconds: spread,
      failure: spread <= _maxSpreadSeconds ? null : CalibrationFailure.unsteady,
    );
  }

  static double _circularMean(List<double> phases) {
    var x = 0.0;
    var y = 0.0;
    for (final phase in phases) {
      x += math.cos(phase);
      y += math.sin(phase);
    }
    return math.atan2(y, x);
  }
}
