import 'dart:math' as math;
import 'dart:typed_data';

/// One detected hit: when it started and how strongly it stood out.
class Onset {
  final double timeSeconds;

  /// The spectral-flux peak height that triggered this onset -- comparable
  /// between onsets of the same recording, not an absolute loudness.
  final double strength;

  const Onset(this.timeSeconds, this.strength);

  @override
  String toString() => 'Onset(${timeSeconds.toStringAsFixed(3)}s, ${strength.toStringAsFixed(0)})';
}

/// Finds the moments percussive hits start in a mono recording, by spectral
/// flux: how much louder each frequency band just got, summed over all bands.
/// A drum hit makes every band jump at once, while a ringing tail only
/// decays, so flux spikes at each attack even when the previous hit is still
/// sounding -- which a plain loudness threshold can't tell apart at fast
/// tempos.
///
/// Analysis is split in two so the cheap half can be re-run with different
/// settings without redoing the expensive half: [analyze] does the FFT work
/// once per recording, [OnsetAnalysis.pickOnsets] turns the result into hits.
class OnsetDetector {
  static const int _frameSize = 512;
  static const int _hopSize = 128;

  /// Flux compares each frame with the one this many hops earlier rather
  /// than the immediately previous one: frames overlap by 75%, so an attack
  /// enters consecutive frames gradually, and a longer lag collects that
  /// whole rise into one tall peak instead of several short ones.
  static const int _fluxLagFrames = 3;

  /// Magnitudes are log-compressed as `log(1 + gain * magnitude)` so a quiet
  /// ghost note and a loud accent produce flux peaks of comparable size,
  /// rather than the accent being 100x taller.
  static const double _compressionGain = 1000;

  static OnsetAnalysis analyze(Int16List samples, {required int sampleRate}) {
    final frameCount =
        samples.length < _frameSize ? 0 : (samples.length - _frameSize) ~/ _hopSize + 1;
    final flux = Float64List(frameCount);
    final computer = _FluxComputer();
    for (var frame = 0; frame < frameCount; frame++) {
      flux[frame] = computer.next(samples, frame * _hopSize);
    }
    return OnsetAnalysis._(flux, _FrameTiming(sampleRate));
  }

  /// FFT bin ranges of the frequency bands flux is measured over: band `b`
  /// covers bins `edges[b]` up to (not including) `edges[b + 1]`, spaced
  /// logarithmically from bin 1 (DC is skipped) to the top of the spectrum.
  ///
  /// Flux is taken per band rather than per FFT bin because noise-like
  /// sound -- snare wires buzzing after a hit, room noise -- makes every
  /// individual bin flicker up and down at random, which reads as constant
  /// flux and buries soft hits played over a ringing tail. Averaging the
  /// bins of a band cancels most of that flicker, while a real attack still
  /// lifts the whole band at once.
  static List<int> _bandEdges() {
    const topBin = _frameSize ~/ 2;
    final edges = <int>[1];
    for (var band = 1; band <= _targetBandCount; band++) {
      final edge = math.pow(topBin + 1, band / _targetBandCount).round();
      // The lowest bands would round to the same bin; give each at least one.
      edges.add(math.min(topBin + 1, math.max(edges.last + 1, edge)));
    }
    return edges;
  }

  static const int _targetBandCount = 32;

  /// Convenience for [analyze] followed by [OnsetAnalysis.pickOnsets] with
  /// default settings.
  static List<Onset> detect(Int16List samples, {required int sampleRate}) =>
      analyze(samples, sampleRate: sampleRate).pickOnsets();
}

/// A recording's spectral-flux curve, ready to have onsets picked from it.
class OnsetAnalysis {
  /// Flux per analysis frame (see [OnsetDetector]).
  final Float64List flux;

  final _FrameTiming _timing;

  OnsetAnalysis._(this.flux, this._timing);

  /// A flux peak must exceed this fraction of the recording's tallest peak
  /// to count as a hit. Lower finds quieter hits but also more noise.
  static const double defaultThreshold = 0.08;

  /// The closest two hits can be: within that distance only the strongest
  /// flux peak is kept. Allows 20 hits per second, twice the app's
  /// 10-per-second requirement.
  static const double defaultMinGapSeconds = 0.05;

  List<Onset> pickOnsets({
    double threshold = defaultThreshold,
    double minGapSeconds = defaultMinGapSeconds,
  }) {
    var maxFlux = 0.0;
    for (final value in flux) {
      if (value > maxFlux) maxFlux = value;
    }
    final picker = _PeakPicker(_timing, threshold: threshold, minGapSeconds: minGapSeconds);

    final onsets = <Onset>[];
    for (var frame = 0; frame < flux.length; frame++) {
      if (picker.isOnset(flux, frame, maxFlux)) onsets.add(_timing.onsetAt(frame, flux[frame]));
    }
    return onsets;
  }
}

/// Finds hits in audio as it arrives, a chunk at a time, for judging a
/// performance while it is still being played. Uses the same flux and the
/// same peak criteria as [OnsetDetector], with two differences forced by not
/// knowing the future: a hit is only reported [latencySeconds] after it
/// happened (a peak can't be called the tallest nearby until what follows it
/// has arrived), and "the tallest peak" its threshold is relative to is the
/// tallest so far rather than of the whole recording.
class StreamingOnsetDetector {
  final _FrameTiming _timing;
  final _PeakPicker _picker;
  final _computer = _FluxComputer();
  final _flux = <double>[];
  var _maxFlux = 0.0;
  var _nextFrameToJudge = 0;

  /// Samples received but not yet consumed by a whole analysis frame.
  var _pending = Int16List(0);
  var _samplesReceived = 0;

  StreamingOnsetDetector({
    required int sampleRate,
    double threshold = OnsetAnalysis.defaultThreshold,
    double minGapSeconds = OnsetAnalysis.defaultMinGapSeconds,
  })  : _timing = _FrameTiming(sampleRate),
        _picker = _PeakPicker(
          _FrameTiming(sampleRate),
          threshold: threshold,
          minGapSeconds: minGapSeconds,
        );

  /// How much audio has been fed in so far.
  double get secondsReceived => _samplesReceived / _timing.sampleRate;

  /// The longest a hit can go unreported after the audio containing it has
  /// been fed in. Any hit earlier than `secondsReceived - latencySeconds`
  /// has already been returned.
  double get latencySeconds =>
      (_picker.gapFrames + 1) * _timing.secondsPerFrame + _timing.frameSeconds;

  /// Feeds in the next stretch of audio and returns the hits it confirmed,
  /// timed from the start of the stream.
  List<Onset> addSamples(Int16List samples) {
    _samplesReceived += samples.length;
    final buffer = Int16List(_pending.length + samples.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, samples);

    var start = 0;
    for (; start + OnsetDetector._frameSize <= buffer.length; start += OnsetDetector._hopSize) {
      final value = _computer.next(buffer, start);
      _flux.add(value);
      if (value > _maxFlux) _maxFlux = value;
    }
    _pending = Int16List.sublistView(buffer, start);

    final onsets = <Onset>[];
    // A frame can be judged once the frames it must out-top have arrived.
    for (; _nextFrameToJudge + _picker.gapFrames < _flux.length; _nextFrameToJudge++) {
      if (_picker.isOnset(_flux, _nextFrameToJudge, _maxFlux)) {
        onsets.add(_timing.onsetAt(_nextFrameToJudge, _flux[_nextFrameToJudge]));
      }
    }
    return onsets;
  }
}

/// Converts between analysis frames and time.
class _FrameTiming {
  final int sampleRate;

  const _FrameTiming(this.sampleRate);

  double get secondsPerFrame => OnsetDetector._hopSize / sampleRate;
  double get frameSeconds => OnsetDetector._frameSize / sampleRate;

  /// The flux peak lands this long after the attack actually starts (the
  /// attack has to be well inside the analysis frame before flux peaks).
  /// Measured against synthetic recordings with known hit times -- see
  /// `onset_detector_test.dart`.
  static const double _peakDelaySeconds = 0.0045;

  Onset onsetAt(int frame, double strength) {
    final time = frame * secondsPerFrame + frameSeconds / 2 - _peakDelaySeconds;
    return Onset(math.max(0, time), strength);
  }
}

/// Decides which frames of a flux curve are hits.
class _PeakPicker {
  final double threshold;
  final int gapFrames;
  final int _medianFrames;

  _PeakPicker(_FrameTiming timing, {required this.threshold, required double minGapSeconds})
      : gapFrames = math.max(1, (minGapSeconds / timing.secondsPerFrame).round()),
        _medianFrames = math.max(1, (_medianWindowSeconds / timing.secondsPerFrame).round());

  /// No flux peak below this counts, however quiet the rest of the recording
  /// is -- otherwise a recording with no hits at all would have its
  /// background noise promoted to "the tallest peak" and reported as hits.
  static const double _absoluteFloor = 5;

  /// A peak must also exceed this multiple of the median flux around it, so
  /// a stretch of steady noise (a fan, a ringing cymbal) raises the bar
  /// locally instead of triggering.
  static const double _medianMultiplier = 1.5;
  static const double _medianWindowSeconds = 0.1;

  /// Whether [flux]`[frame]` is a hit: tall enough relative to [maxFlux],
  /// the tallest within [gapFrames] either side, and standing clear of the
  /// flux around it. Looks at most [gapFrames] past [frame] for the
  /// local-maximum test, and as far past it as [flux] goes (up to the median
  /// window) for the median.
  bool isOnset(List<double> flux, int frame, double maxFlux) {
    final value = flux[frame];
    final baseThreshold = math.max(_absoluteFloor, threshold * maxFlux);
    if (value < baseThreshold) return false;
    if (!_isLocalMax(flux, frame)) return false;
    return value >= baseThreshold + _medianMultiplier * _medianAround(flux, frame);
  }

  /// Ties go to the earliest frame, so a flat-topped peak yields one onset.
  bool _isLocalMax(List<double> flux, int frame) {
    final value = flux[frame];
    final from = math.max(0, frame - gapFrames);
    final to = math.min(flux.length - 1, frame + gapFrames);
    for (var i = from; i <= to; i++) {
      if (flux[i] > value || (flux[i] == value && i < frame)) return false;
    }
    return true;
  }

  double _medianAround(List<double> flux, int frame) {
    final from = math.max(0, frame - _medianFrames);
    final to = math.min(flux.length, frame + _medianFrames + 1);
    final window = flux.sublist(from, to)..sort();
    return window[window.length ~/ 2];
  }
}

/// Computes spectral flux frame by frame, remembering the few previous
/// frames each new one is compared against. Frames must be fed in order.
class _FluxComputer {
  static const int _frameSize = OnsetDetector._frameSize;

  final _fft = _Fft(_frameSize);
  final List<int> _bandEdges = OnsetDetector._bandEdges();
  final _re = Float64List(_frameSize);
  final _im = Float64List(_frameSize);

  /// Ring of the last (lag + 1) frames' compressed band levels.
  late final List<Float64List> _history = List.generate(
    OnsetDetector._fluxLagFrames + 1,
    (_) => Float64List(_bandEdges.length - 1),
  );
  var _frame = 0;

  /// Flux of the frame starting at [samples]`[start]`.
  double next(Int16List samples, int start) {
    for (var i = 0; i < _frameSize; i++) {
      _re[i] = samples[start + i] * _fft.window[i];
      _im[i] = 0;
    }
    _fft.transform(_re, _im);

    // Scales a full-scale sine to magnitude 1 regardless of frame size.
    final magnitudeScale = 2 / (_fft.windowSum * 32768);
    final bandCount = _bandEdges.length - 1;
    final current = _history[_frame % _history.length];
    for (var band = 0; band < bandCount; band++) {
      var power = 0.0;
      for (var bin = _bandEdges[band]; bin < _bandEdges[band + 1]; bin++) {
        power += _re[bin] * _re[bin] + _im[bin] * _im[bin];
      }
      final magnitude = math.sqrt(power / (_bandEdges[band + 1] - _bandEdges[band]));
      current[band] =
          math.log(1 + OnsetDetector._compressionGain * magnitudeScale * magnitude);
    }

    var flux = 0.0;
    if (_frame >= OnsetDetector._fluxLagFrames) {
      final previous = _history[(_frame - OnsetDetector._fluxLagFrames) % _history.length];
      for (var band = 0; band < bandCount; band++) {
        final rise = current[band] - previous[band];
        if (rise > 0) flux += rise;
      }
    }
    _frame++;
    return flux;
  }
}

/// In-place radix-2 FFT of a fixed size, with a Hann window to go with it.
class _Fft {
  final int size;
  final Float64List window;
  final double windowSum;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _bitReversed;

  _Fft._(this.size, this.window, this.windowSum, this._cos, this._sin, this._bitReversed);

  factory _Fft(int size) {
    assert(size > 1 && size & (size - 1) == 0, 'FFT size must be a power of two');
    final window = Float64List(size);
    var windowSum = 0.0;
    for (var i = 0; i < size; i++) {
      window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / size);
      windowSum += window[i];
    }
    final cos = Float64List(size ~/ 2);
    final sin = Float64List(size ~/ 2);
    for (var i = 0; i < size ~/ 2; i++) {
      cos[i] = math.cos(2 * math.pi * i / size);
      sin[i] = math.sin(2 * math.pi * i / size);
    }
    final bits = size.bitLength - 1;
    final bitReversed = Int32List(size);
    for (var i = 0; i < size; i++) {
      var reversed = 0;
      for (var bit = 0; bit < bits; bit++) {
        if (i & (1 << bit) != 0) reversed |= 1 << (bits - 1 - bit);
      }
      bitReversed[i] = reversed;
    }
    return _Fft._(size, window, windowSum, cos, sin, bitReversed);
  }

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < size; i++) {
      final j = _bitReversed[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var span = 2; span <= size; span <<= 1) {
      final half = span >> 1;
      final step = size ~/ span;
      for (var start = 0; start < size; start += span) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = -_sin[k * step];
          final a = start + k;
          final b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}
