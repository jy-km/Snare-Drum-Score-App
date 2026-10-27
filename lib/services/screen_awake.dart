import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the phone's screen from dimming and locking -- while practising,
/// the player's hands are on the sticks, not the screen.
abstract class ScreenAwake {
  /// Keeps the screen on ([on]) or lets it sleep again as usual.
  Future<void> keep(bool on);
}

/// The phone's own screen, through `wakelock_plus`.
class DeviceScreenAwake implements ScreenAwake {
  const DeviceScreenAwake();

  @override
  Future<void> keep(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      // Only the screen dims as usual; practice goes on.
      debugPrint('Could not ${on ? 'keep the screen on' : 'release the screen'}: $e');
    }
  }
}
