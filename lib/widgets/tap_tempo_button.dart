import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tap_tempo.dart';

/// A "Tap" button for setting a tempo by tapping the beat: from the second
/// tap on, [onTempo] gets the tempo the taps make (see [TapTempo]), and
/// keeps getting it, steadier, as tapping goes on.
class TapTempoButton extends StatefulWidget {
  final int minBpm;
  final int maxBpm;
  final ValueChanged<int> onTempo;

  /// Off, the button is shown disabled and taps do nothing.
  final bool enabled;

  const TapTempoButton({
    super.key,
    required this.minBpm,
    required this.maxBpm,
    required this.onTempo,
    this.enabled = true,
  });

  @override
  State<TapTempoButton> createState() => _TapTempoButtonState();
}

class _TapTempoButtonState extends State<TapTempoButton> {
  late final _tapTempo = TapTempo(minBpm: widget.minBpm, maxBpm: widget.maxBpm);

  void _tap() {
    HapticFeedback.selectionClick();
    final bpm = _tapTempo.tap(clock.now());
    if (bpm != null) widget.onTempo(bpm);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tap the beat to set the tempo',
      // Counts the moment the finger lands, not when it lifts: a tap's
      // timing is when it hits, as on a drum. The button itself only shows
      // the press.
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _tap() : null,
        child: OutlinedButton.icon(
          onPressed: widget.enabled ? () {} : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 40),
          ),
          icon: const Icon(Icons.touch_app_outlined, size: 18),
          label: const Text('Tap'),
        ),
      ),
    );
  }
}
