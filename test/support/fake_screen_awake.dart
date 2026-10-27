import 'package:snare_drum_score_app/services/screen_awake.dart';

/// Remembers whether the screen is being kept on, instead of doing it.
class FakeScreenAwake implements ScreenAwake {
  bool keptOn = false;

  @override
  Future<void> keep(bool on) async => keptOn = on;
}
