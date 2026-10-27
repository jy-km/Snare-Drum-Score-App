import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Confetti falling over the screen once, for a run worth celebrating --
/// more of it, slower, for a [perfect] one. It never takes a tap: whatever
/// is underneath works as usual while it falls. Skipped when the phone asks
/// for less motion.
class ConfettiBurst extends StatefulWidget {
  final bool perfect;

  const ConfettiBurst({super.key, this.perfect = false});

  static const Duration duration = Duration(milliseconds: 3000);

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: widget.perfect ? ConfettiBurst.duration * 1.4 : ConfettiBurst.duration,
  )..forward();

  late final List<_Piece> _pieces = () {
    final random = math.Random();
    return List.generate(widget.perfect ? 150 : 90, (_) => _Piece.random(random));
  }();

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final colors = [
      palette.perfect,
      palette.great,
      palette.good,
      palette.accent,
      palette.fail,
      if (widget.perfect) ...[palette.perfect, palette.perfect],
    ];
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_fall, _pieces, colors)),
      ),
    );
  }
}

/// One piece of confetti: where it starts and how it falls, sways and spins,
/// all as fractions of the screen and of the fall.
class _Piece {
  final double x;
  final double startY;
  final double fallDistance;
  final double sway;
  final double swayTurns;
  final double spinTurns;
  final double width;
  final double height;
  final int colorIndex;

  _Piece.random(math.Random random)
    : x = random.nextDouble(),
      startY = -0.05 - random.nextDouble() * 0.35,
      fallDistance = 0.8 + random.nextDouble() * 0.6,
      sway = 0.01 + random.nextDouble() * 0.04,
      swayTurns = 0.5 + random.nextDouble() * 1.5,
      spinTurns = (random.nextDouble() * 2 - 1) * 3,
      width = 6 + random.nextDouble() * 5,
      height = 3 + random.nextDouble() * 3,
      colorIndex = random.nextInt(1 << 16);
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> fall;
  final List<_Piece> pieces;
  final List<Color> colors;

  _ConfettiPainter(this.fall, this.pieces, this.colors) : super(repaint: fall);

  @override
  void paint(Canvas canvas, Size size) {
    final t = fall.value;
    if (t >= 1) return;
    // Fades out over the last fifth of the fall.
    final opacity = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    final paint = Paint();
    for (final piece in pieces) {
      // Falls fast at first and slows, as if catching the air.
      final progress = 1 - math.pow(1 - t, 1.6).toDouble();
      final y = (piece.startY + piece.fallDistance * progress) * size.height;
      if (y < -20 || y > size.height + 20) continue;
      final x = (piece.x + piece.sway * math.sin(2 * math.pi * piece.swayTurns * t)) * size.width;
      paint.color = colors[piece.colorIndex % colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(2 * math.pi * piece.spinTurns * t);
      // Seen edge-on as it tumbles: narrower and wider in turn.
      final tumble = math.cos(2 * math.pi * piece.spinTurns * t * 1.3).abs();
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.width,
          height: piece.height * (0.3 + 0.7 * tumble),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.pieces != pieces || oldDelegate.colors != colors;
}
