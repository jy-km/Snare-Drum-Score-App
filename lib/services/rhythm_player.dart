import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../models/rhythm_score.dart';
import 'click_sound.dart';

class PlaybackPosition {
  final int measureIndex;
  final int cellIndex;

  const PlaybackPosition(this.measureIndex, this.cellIndex);
}

/// Plays a [RhythmScore] at a given tempo by rendering the whole sequence to
/// a single linear audio buffer up front (mixing each hit's click waveform in
/// at its exact sample position, like bouncing a MIDI track to audio) and
/// playing that buffer once.
///
/// An earlier version retriggered two long-lived players live via
/// seek()+resume() per hit. That was unreliable: audioplayers' seek()/resume()
/// are async platform-channel round-trips that don't complete fast or
/// deterministically enough relative to typical tempos, which caused
/// spurious extra retriggers when two calls overlapped, and made repeat
/// playthroughs of the same pattern sound different. Rendering once and
/// playing back linearly has no retrigger window, so it's deterministic by
/// construction, and takes tempo as a parameter (not the score's stored
/// tempo) so Milestone 2 can reuse it with an independent practice tempo.
class RhythmPlayer {
  final _player = AudioPlayer(playerId: 'rhythm_player');
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  bool _isPlaying = false;

  final _positionController = StreamController<PlaybackPosition?>.broadcast();

  bool get isPlaying => _isPlaying;

  Stream<PlaybackPosition?> get positionStream => _positionController.stream;

  Future<void> play(RhythmScore score, {int? tempoBpmOverride}) async {
    await stop();

    final tempoBpm = tempoBpmOverride ?? score.tempoBpm;
    final msPerCell = 60000 / tempoBpm / RhythmGrid.subdivisionsPerBeat;
    final totalCells = score.measures.length * RhythmGrid.cellsPerMeasure;
    final wavBytes = _renderSequence(score, msPerCell: msPerCell);

    _isPlaying = true;
    _positionSubscription = _player.onPositionChanged.listen((position) {
      final cellIndex = (position.inMicroseconds / 1000 / msPerCell)
          .floor()
          .clamp(0, totalCells - 1);
      _positionController.add(
        PlaybackPosition(
          cellIndex ~/ RhythmGrid.cellsPerMeasure,
          cellIndex % RhythmGrid.cellsPerMeasure,
        ),
      );
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) => _stopInternal());

    await _player.play(BytesSource(wavBytes));
  }

  /// Mixes each hit's click samples into a silent buffer at its exact sample
  /// position, producing one continuous WAV covering the whole score.
  Uint8List _renderSequence(RhythmScore score, {required double msPerCell}) {
    final samplesPerCell = (ClickSound.sampleRate * msPerCell / 1000).round();
    final totalCells = score.measures.length * RhythmGrid.cellsPerMeasure;
    final tailLength = ClickSound.normalClickSamples.length;
    final mixBuffer = Int32List(totalCells * samplesPerCell + tailLength);

    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++) {
      final measure = score.measures[measureIndex];
      for (var cellInMeasure = 0; cellInMeasure < measure.beats.length; cellInMeasure++) {
        final beat = measure.beats[cellInMeasure];
        if (beat.isRest) continue;

        final cellIndex = measureIndex * RhythmGrid.cellsPerMeasure + cellInMeasure;
        final startSample = cellIndex * samplesPerCell;
        final clickSamples = beat.state == BeatState.accent
            ? ClickSound.accentClickSamples
            : ClickSound.normalClickSamples;
        for (var i = 0; i < clickSamples.length; i++) {
          mixBuffer[startSample + i] += clickSamples[i];
        }
      }
    }

    final finalSamples = Int16List(mixBuffer.length);
    for (var i = 0; i < mixBuffer.length; i++) {
      finalSamples[i] = mixBuffer[i].clamp(-32768, 32767);
    }
    return ClickSound.pcm16ToWav(finalSamples);
  }

  Future<void> stop() async {
    await _player.stop();
    _stopInternal();
  }

  void _stopInternal() {
    _isPlaying = false;
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    _positionController.add(null);
  }

  Future<void> dispose() async {
    _stopInternal();
    await _player.dispose();
    await _positionController.close();
  }
}
