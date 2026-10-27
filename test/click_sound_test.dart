import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/services/click_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Every instrument\'s WAV asset decodes to non-empty mono PCM', () async {
    for (final instrument in Instrument.values) {
      final samples = await ClickSound.accentSamples(instrument);
      expect(samples.isNotEmpty, isTrue, reason: '$instrument decoded to no samples');
    }
  });

  test('normalSamples is accentSamples attenuated, not a different recording', () async {
    final accent = await ClickSound.accentSamples(Instrument.kick);
    final normal = await ClickSound.normalSamples(Instrument.kick);

    expect(normal.length, equals(accent.length));
    final accentPeak = accent.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
    final normalPeak = normal.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
    expect(normalPeak, closeTo(accentPeak * 0.5, accentPeak * 0.05));
  });

  test('preload populates the cache for every instrument without throwing', () async {
    await ClickSound.preload();
    for (final instrument in Instrument.values) {
      expect(await ClickSound.accentSamples(instrument), isNotEmpty);
    }
  });

  test('Marcato is at least as loud as the accent, and a grace stroke much quieter', () async {
    int peak(List<int> samples) => samples.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
    final accent = peak(await ClickSound.accentSamples(Instrument.snare));
    final normal = peak(await ClickSound.normalSamples(Instrument.snare));

    expect(peak(await ClickSound.marcatoSamples(Instrument.snare)), greaterThan(accent));
    expect(peak(await ClickSound.graceSamples(Instrument.snare)), lessThan(normal));
    // The kick's recording is already at full volume: no louder, no clipping.
    expect(
      peak(await ClickSound.marcatoSamples(Instrument.kick)),
      peak(await ClickSound.accentSamples(Instrument.kick)),
    );
  });

  test('Grace strokes come just before their note, closing up at fast tempos', () {
    const msPerUnit = 60000 / 100 / RhythmGrid.unitsPerQuarterNote; // 100 BPM
    int samples(double ms) => (ms * ClickSound.sampleRate / 1000).round();

    expect(ClickSound.graceLeadSamples(Ornament.none, msPerUnit), isEmpty);
    expect(ClickSound.graceLeadSamples(Ornament.flam, msPerUnit), [samples(30)]);
    expect(ClickSound.graceLeadSamples(Ornament.drag, msPerUnit), [samples(60), samples(30)]);

    // At 300 BPM a sixteenth is 50ms: a drag's strokes fit inside it.
    const fastMsPerUnit = 60000 / 300 / RhythmGrid.unitsPerQuarterNote;
    expect(ClickSound.graceLeadSamples(Ornament.drag, fastMsPerUnit), [samples(50), samples(25)]);
  });

  test('A roll sounds a stroke every sixteenth for the length of its note', () {
    List<int> strokes(NoteValue value, [Ornament ornament = Ornament.roll]) =>
        ClickSound.rollStrokeUnits(RhythmEvent(value, EventType.normal, ornament: ornament));

    expect(strokes(NoteValue.quarter), [3, 6, 9], reason: 'four strokes with the note itself');
    expect(strokes(NoteValue.half), [3, 6, 9, 12, 15, 18, 21]);
    expect(strokes(NoteValue.eighth), [3]);
    expect(strokes(NoteValue.sixteenth), isEmpty);
    expect(strokes(NoteValue.eighthTriplet), isEmpty, reason: 'no room for a second sixteenth');
    expect(strokes(NoteValue.quarter, Ornament.none), isEmpty);
    expect(strokes(NoteValue.quarter, Ornament.flam), isEmpty);
  });
}
