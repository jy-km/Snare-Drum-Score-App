import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/midi_score_codec.dart';

void main() {
  test('RhythmScore round-trips through MIDI bytes', () {
    var score = RhythmScore.empty(title: 'Test Rhythm', tempoBpm: 120);

    var measure0 = score.measures[0];
    measure0 = measure0.copyWithBeat(0, const Beat(BeatState.normal));
    measure0 = measure0.copyWithBeat(4, const Beat(BeatState.accent));
    measure0 = measure0.copyWithBeat(8, const Beat(BeatState.normal));
    measure0 = measure0.copyWithBeat(12, const Beat(BeatState.accent));
    score = score.copyWithMeasure(0, measure0);

    var measure7 = score.measures[7];
    measure7 = measure7.copyWithBeat(15, const Beat(BeatState.accent));
    score = score.copyWithMeasure(7, measure7);

    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);

    expect(decoded, equals(score));
  });

  test('Empty score round-trips to all rests', () {
    final score = RhythmScore.empty(title: 'Silence', tempoBpm: 80);
    final bytes = MidiScoreCodec.encode(score);
    final decoded = MidiScoreCodec.decode(bytes);
    expect(decoded, equals(score));
  });
}
