import 'package:flutter/material.dart';

import '../services/hit_judge.dart';
import '../services/run_review.dart';
import 'app_theme.dart';
import 'judgement_style.dart';

/// How early or late each hit of a run was, hit by hit: a dot per note,
/// across in the order (and at the time) the notes came, up for early and
/// down for late, in its judgement's colour. Shaded around the middle is the
/// Perfect window. A note nobody hit is a cross in the row underneath; a
/// hit during a rest has no note to be early or late for and isn't shown.
///
/// Tapping a dot picks it: the line above the chart says which note it was
/// and by how much, and [onSelect] hears about it.
class OffsetChart extends StatefulWidget {
  final RunReview review;
  final ValueChanged<JudgedHit>? onSelect;

  const OffsetChart({super.key, required this.review, this.onSelect});

  /// The plot's height, not counting the missed-note row and the measure
  /// numbers under it.
  static const double plotHeight = 160;

  /// The furthest a hit can be from its note, either way, and still be
  /// judged on it -- the edges of the plot.
  static double get rangeSeconds => Judgement.good.windowSeconds;

  /// Where a hit [offsetSeconds] from its note goes, from 0 at the top
  /// (earliest) to 1 at the bottom (latest).
  static double yFraction(double offsetSeconds) =>
      ((offsetSeconds + rangeSeconds) / (2 * rangeSeconds)).clamp(0.0, 1.0);

  @override
  State<OffsetChart> createState() => _OffsetChartState();
}

class _OffsetChartState extends State<OffsetChart> {
  JudgedHit? _selected;

  static const double _missRowHeight = 18;
  static const double _axisHeight = 18;
  static const double _gutter = 40;
  static const double _rightPadding = 10;

  /// The notes shown: everything judged against a note, in note order.
  late final List<JudgedHit> _hits = [
    for (final hit in widget.review.judgements)
      if (hit.noteIndex != null) hit,
  ]..sort((a, b) => a.noteIndex!.compareTo(b.noteIndex!));

  RunReview get _review => widget.review;

  double get _startSeconds => _review.layout.starts[1] * _review.secondsPerUnit;
  double get _endSeconds => _review.layout.starts.last * _review.secondsPerUnit;

  /// Space inside the plot's frame at either end, so the first and last
  /// notes' dots aren't cut by it.
  static const double _inset = 10;

  double _x(double seconds, double width) {
    final span = _endSeconds - _startSeconds;
    final plotWidth = width - _gutter - _rightPadding - 2 * _inset;
    return _gutter + _inset + (seconds - _startSeconds) / span * plotWidth;
  }

  /// The note nearest a tap at [dx], if any is close enough to mean it.
  JudgedHit? _hitAt(double dx, double width) {
    JudgedHit? nearest;
    var best = 24.0; // a finger's width either side
    for (final hit in _hits) {
      final distance = (_x(_review.noteTimes[hit.noteIndex!], width) - dx).abs();
      if (distance < best) {
        best = distance;
        nearest = hit;
      }
    }
    return nearest;
  }

  void _select(JudgedHit hit) {
    setState(() => _selected = hit);
    widget.onSelect?.call(hit);
  }

  String _caption(JudgedHit hit) {
    final where = _review.locate(hit);
    final offset = hit.offsetSeconds;
    if (offset == null) return '$where: not played';
    final side = offset.abs() < 0.0005 ? 'on time' : (offset < 0 ? 'early' : 'late');
    return '$where: ${judgementLabelWithDirection(hit)}, ${offsetText(offset)} ($side)';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selected == null ? 'Tap a dot to see which note it was.' : _caption(selected),
          key: const Key('offset_chart_caption'),
          style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final hit = _hitAt(details.localPosition.dx, width);
                if (hit != null) _select(hit);
              },
              child: CustomPaint(
                size: Size(width, OffsetChart.plotHeight + _missRowHeight + _axisHeight),
                painter: _OffsetChartPainter(
                  state: this,
                  palette: palette,
                  labelStyle: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                    color: palette.mutedInk,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  selected: selected,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _Key(palette: palette),
      ],
    );
  }
}

class _OffsetChartPainter extends CustomPainter {
  final _OffsetChartState state;
  final AppPalette palette;
  final TextStyle labelStyle;
  final JudgedHit? selected;

  _OffsetChartPainter({
    required this.state,
    required this.palette,
    required this.labelStyle,
    required this.selected,
  });

  static const double _plotTop = 8;

  @override
  void paint(Canvas canvas, Size size) {
    const plotHeight = OffsetChart.plotHeight - _plotTop;
    final left = _OffsetChartState._gutter;
    final right = size.width - _OffsetChartState._rightPadding;
    double y(double offsetSeconds) => _plotTop + OffsetChart.yFraction(offsetSeconds) * plotHeight;
    final hairline = Paint()
      ..color = palette.rule
      ..strokeWidth = 1;

    // The Perfect window, and the lines between the judgements' windows.
    final perfect = Judgement.perfect.windowSeconds;
    canvas.drawRect(
      Rect.fromLTRB(left, y(-perfect), right, y(perfect)),
      Paint()..color = palette.rule.withValues(alpha: 0.45),
    );
    for (final seconds in [-0.12, -0.08, -0.04, 0.04, 0.08, 0.12]) {
      canvas.drawLine(Offset(left, y(seconds)), Offset(right, y(seconds)), hairline);
    }
    canvas.drawLine(
      Offset(left, y(0)),
      Offset(right, y(0)),
      Paint()
        ..color = palette.mutedInk
        ..strokeWidth = 1,
    );

    // Milliseconds in the margin, with the plot's two edges named for which
    // way they are: the earliest at the top, the latest at the bottom.
    for (final seconds in [-0.08, -0.04, 0.0, 0.04, 0.08]) {
      final ms = (seconds * 1000).round();
      _label(
        canvas,
        ms == 0 ? '0' : (ms > 0 ? '+$ms' : '−${-ms}'),
        Offset(left - 4, y(seconds)),
        alignRight: true,
      );
    }
    final words = labelStyle.copyWith(letterSpacing: 0.5);
    _label(canvas, 'EARLY', Offset(left - 4, y(-0.12)), alignRight: true, style: words);
    _label(canvas, 'LATE', Offset(left - 4, y(0.12)), alignRight: true, style: words);

    // Measures: a hairline between each two, and each one's number underneath.
    final layout = state._review.layout;
    final missRowY = OffsetChart.plotHeight + _OffsetChartState._missRowHeight / 2;
    final axisY =
        OffsetChart.plotHeight +
        _OffsetChartState._missRowHeight +
        _OffsetChartState._axisHeight / 2;
    for (var measure = 1; measure < layout.measureCount; measure++) {
      final x = state._x(layout.starts[measure] * state._review.secondsPerUnit, size.width);
      // The first measure starts at the frame, which already marks it.
      if (measure > 1) canvas.drawLine(Offset(x, _plotTop), Offset(x, missRowY + 6), hairline);
      final next = state._x(layout.starts[measure + 1] * state._review.secondsPerUnit, size.width);
      _label(
        canvas,
        '${measure + layout.firstMeasureNumber - 1}',
        Offset((x + next) / 2, axisY),
        center: true,
      );
    }
    for (final edge in [left, right]) {
      canvas.drawLine(Offset(edge, _plotTop), Offset(edge, missRowY + 6), hairline);
    }

    for (final hit in state._hits) {
      final x = state._x(state._review.noteTimes[hit.noteIndex!], size.width);
      final color = judgementColor(hit.judgement, palette);
      final isSelected = identical(hit, selected);
      final offset = hit.offsetSeconds;
      if (offset == null) {
        // Not played: a cross in the row under the plot.
        const arm = 4.0;
        final cross = Paint()
          ..color = color
          ..strokeWidth = isSelected ? 3 : 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x - arm, missRowY - arm), Offset(x + arm, missRowY + arm), cross);
        canvas.drawLine(Offset(x - arm, missRowY + arm), Offset(x + arm, missRowY - arm), cross);
        continue;
      }
      final center = Offset(x, y(offset));
      final radius = isSelected ? 6.0 : 4.0;
      // A ring in the page's colour keeps dots apart where they crowd.
      canvas.drawCircle(center, radius + 2, Paint()..color = palette.surface);
      if (isSelected) canvas.drawCircle(center, radius + 2, Paint()..color = palette.ink);
      canvas.drawCircle(center, radius, Paint()..color = color);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    bool alignRight = false,
    bool center = false,
    TextStyle? style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - painter.width : (center ? at.dx - painter.width / 2 : at.dx);
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_OffsetChartPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.palette != palette ||
      oldDelegate.labelStyle != labelStyle;
}

/// Which colour is which judgement: the dot (or cross) beside its name,
/// the name itself in ink.
class _Key extends StatelessWidget {
  final AppPalette palette;

  const _Key({required this.palette});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final judgement in const [
          Judgement.perfect,
          Judgement.great,
          Judgement.good,
          Judgement.miss,
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              judgement == Judgement.miss
                  ? Icon(Icons.close, size: 12, color: judgementColor(judgement, palette))
                  : Icon(Icons.circle, size: 9, color: judgementColor(judgement, palette)),
              const SizedBox(width: 4),
              Text(
                judgement == Judgement.miss ? 'Miss (not played)' : judgementLabel(judgement),
                style: style,
              ),
            ],
          ),
      ],
    );
  }
}
