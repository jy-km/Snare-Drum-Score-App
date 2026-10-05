import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// What this phone's "sound delay" has measured as on recent practice runs.
///
/// The sound delay is the gap between when the app's own clocks say the
/// count-in started and when the microphone actually heard it start -- the
/// time the phone takes to get sound out of the speaker and back in through
/// the mic. Each run that hears its count-in measures it; a run that doesn't
/// hear it can borrow [typical] to place hits on the timeline anyway.
class MicLatencyHistory {
  /// Measured delays in seconds, oldest first.
  final List<double> measurements;

  MicLatencyHistory([List<double> measurements = const []])
      : measurements = List.unmodifiable(
          measurements.length > _kept
              ? measurements.sublist(measurements.length - _kept)
              : measurements,
        );

  static const int _kept = 9;

  /// Fewer measurements than this are too few to judge a run by: one odd
  /// run would decide every judgement of the next.
  static const int _reliableCount = 3;

  MicLatencyHistory adding(double seconds) => MicLatencyHistory([...measurements, seconds]);

  /// The middle measurement -- unmoved by the occasional outlier -- or null
  /// if there are none.
  double? get typical {
    if (measurements.isEmpty) return null;
    final sorted = [...measurements]..sort();
    return sorted[sorted.length ~/ 2];
  }

  bool get isReliable => measurements.length >= _reliableCount;
}

/// Keeps the sound delay the player measured themselves in calibration mode
/// (see `TapCalibration`) between app launches. Unlike [MicLatencyHistory],
/// which the app gathers on its own through the phone's speaker, this one
/// is measured through whatever the player was listening on -- so it is
/// the one to go by when a run can't hear its own count-in.
abstract class MicCalibrationStore {
  /// The saved offset in seconds, or null if never calibrated (or cleared).
  Future<double?> load();

  /// Saves [offsetSeconds], or clears the calibration if null.
  Future<void> save(double? offsetSeconds);
}

/// Stores the calibration as a small JSON file in the app's documents
/// directory.
class FileMicCalibrationStore implements MicCalibrationStore {
  const FileMicCalibrationStore();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mic_calibration.json');
  }

  @override
  Future<double?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (decoded['offsetSeconds'] as num?)?.toDouble();
  }

  @override
  Future<void> save(double? offsetSeconds) async {
    final file = await _file();
    if (offsetSeconds == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(jsonEncode({'offsetSeconds': offsetSeconds}));
  }
}

/// Keeps a [MicLatencyHistory] between app launches.
abstract class MicLatencyStore {
  Future<MicLatencyHistory> load();
  Future<void> save(MicLatencyHistory history);
}

/// Stores the history as a small JSON file in the app's documents directory.
class FileMicLatencyStore implements MicLatencyStore {
  const FileMicLatencyStore();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mic_latency.json');
  }

  @override
  Future<MicLatencyHistory> load() async {
    final file = await _file();
    if (!await file.exists()) return MicLatencyHistory();
    final decoded = jsonDecode(await file.readAsString());
    return MicLatencyHistory([for (final value in decoded as List) (value as num).toDouble()]);
  }

  @override
  Future<void> save(MicLatencyHistory history) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(history.measurements));
  }
}
