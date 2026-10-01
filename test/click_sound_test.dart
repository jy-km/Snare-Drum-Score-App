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
}
