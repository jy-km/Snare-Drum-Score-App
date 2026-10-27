import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A small light beside a microphone that flashes each time the microphone
/// hears a hit -- any hit, judged or not, the count-in's clicks included --
/// so the player can see the app is hearing them before a run's results
/// say so.
class MicLight extends StatefulWidget {
  /// How many hits the microphone has heard so far. The light flashes each
  /// time this goes up.
  final int heardCount;

  /// Whether the microphone is on. Off, the light is not shown.
  final bool listening;

  static const double width = 40;

  const MicLight({super.key, required this.heardCount, required this.listening});

  @override
  State<MicLight> createState() => _MicLightState();
}

class _MicLightState extends State<MicLight> with SingleTickerProviderStateMixin {
  /// 0 just after a hit (lit), running up to 1 (dim).
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void didUpdateWidget(MicLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.heardCount > oldWidget.heardCount) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.listening) return const SizedBox(width: MicLight.width);
    final palette = AppPalette.of(context);
    return SizedBox(
      width: MicLight.width,
      child: Semantics(
        label: 'Microphone on',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.mic_none, size: 16, color: palette.mutedInk),
            const SizedBox(width: 2),
            AnimatedBuilder(
              animation: _fade,
              builder: (context, _) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(palette.accent, palette.rule, _fade.value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
