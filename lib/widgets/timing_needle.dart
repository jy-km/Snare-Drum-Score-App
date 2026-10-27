import 'package:flutter/material.dart';

import '../services/hit_judge.dart';
import 'app_theme.dart';
import 'judgement_style.dart';

/// A strip showing how early or late the player's latest hits were: a tick
/// for each, left of centre for early and right for late, newest boldest and
/// older ones fading. A run of ticks off to one side is the player rushing
/// or dragging, which a single "Great-" can't show.
///
/// Spans the Good window either way; the shaded middle is the Perfect
/// window.
class TimingNeedle extends StatelessWidget {
  /// The hits to show, oldest first -- each with an offset from its note
  /// ([recent] picks them out).
  final List<JudgedHit> hits;

  static const double height = 28;

  /// How many of the latest hits are shown.
  static const int trailLength = 8;

  const TimingNeedle({super.key, required this.hits});

  /// The last [trailLength] of [judgements] that were hits on a note --
  /// misses and fails have no early or late.
  static List<JudgedHit> recent(Iterable<JudgedHit> judgements) {
    final hits = [
      for (final hit in judgements)
        if (hit.offsetSeconds != null) hit,
    ];
    return hits.length <= trailLength ? hits : hits.sublist(hits.length - trailLength);
  }

  /// Where across the strip (0 at the left edge, 1 at the right) a hit
  /// [offsetSeconds] from its note goes. Beyond the Good window, it sits at
  /// the edge.
  static double positionOf(double offsetSeconds) {
    final range = Judgement.good.windowSeconds;
    return (0.5 + offsetSeconds / (2 * range)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: palette.mutedInk, letterSpacing: 0.5);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('EARLY', style: labelStyle)),
          Expanded(
            child: CustomPaint(
              size: const Size.fromHeight(height),
              painter: _NeedlePainter(hits: hits, palette: palette),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('LATE', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final List<JudgedHit> hits;
  final AppPalette palette;

  _NeedlePainter({required this.hits, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    double x(double offsetSeconds) => TimingNeedle.positionOf(offsetSeconds) * size.width;
    final midY = size.height / 2;

    final perfect = Judgement.perfect.windowSeconds;
    canvas.drawRect(
      Rect.fromLTRB(x(-perfect), 4, x(perfect), size.height - 4),
      Paint()..color = palette.rule.withValues(alpha: 0.6),
    );
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = palette.rule
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(size.width / 2, 2),
      Offset(size.width / 2, size.height - 2),
      Paint()
        ..color = palette.mutedInk
        ..strokeWidth = 1,
    );

    for (final (index, hit) in hits.indexed) {
      final newest = index == hits.length - 1;
      // Fades from the newest back; the oldest shown is still just visible.
      final opacity = newest ? 1.0 : 0.3 + 0.45 * (index + 1) / hits.length;
      final reach = newest ? size.height / 2 : size.height * 0.3;
      final tickX = x(hit.offsetSeconds!);
      canvas.drawLine(
        Offset(tickX, midY - reach),
        Offset(tickX, midY + reach),
        Paint()
          ..color = judgementColor(hit.judgement, palette).withValues(alpha: opacity)
          ..strokeWidth = newest ? 4 : 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_NeedlePainter oldDelegate) =>
      oldDelegate.hits != hits || oldDelegate.palette != palette;
}
