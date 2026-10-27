import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/practice_history.dart';

/// "Oct 7".
String shortDate(DateTime day) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[day.month - 1]} ${day.day}';
}

/// Groups [runs] by the local calendar day they were played on, oldest day
/// first.
Map<DateTime, List<PracticeRun>> _runsByDay(Iterable<PracticeRun> runs) {
  final byDay = <DateTime, List<PracticeRun>>{};
  for (final run in runs) {
    final local = run.startedAt.toLocal();
    (byDay[DateTime(local.year, local.month, local.day)] ??= []).add(run);
  }
  return {for (final day in byDay.keys.toList()..sort()) day: byDay[day]!};
}

/// One day's point on [AccuracyByDayChart]: the average accuracy of every
/// run that day.
class DailyAccuracy {
  final DateTime day;
  final double averageAccuracy;
  final int runCount;

  const DailyAccuracy(this.day, this.averageAccuracy, this.runCount);

  /// One per day practised, oldest first. Runs with nothing judged (no
  /// accuracy) are left out.
  static List<DailyAccuracy> fromRuns(Iterable<PracticeRun> runs) => [
    for (final MapEntry(key: day, value: dayRuns) in _runsByDay(runs).entries)
      if ([for (final run in dayRuns) ?run.accuracy] case final accuracies
          when accuracies.isNotEmpty)
        DailyAccuracy(
          day,
          accuracies.reduce((a, b) => a + b) / accuracies.length,
          accuracies.length,
        ),
  ];
}

/// One day's point on [TempoByDayChart]: the tempos played that day.
class DailyTempo {
  final DateTime day;

  /// The fastest tempo played that day -- the point plotted, since the
  /// climb toward the target tempo is what the chart is for.
  final int topBpm;
  final int slowestBpm;
  final int runCount;

  const DailyTempo(this.day, this.topBpm, this.slowestBpm, this.runCount);

  /// One per day practised, oldest first; every run counts, whatever tempo
  /// it was played at. Tempos are counted in [beat] notes, so runs played
  /// while the track's BPM counted a different note still compare.
  static List<DailyTempo> fromRuns(
    Iterable<PracticeRun> runs, {
    TempoBeat beat = TempoBeat.quarter,
  }) {
    int bpm(PracticeRun run) => beat.convert(run.tempoBpm, run.tempoBeat).round();
    return [
      for (final MapEntry(key: day, value: dayRuns) in _runsByDay(runs).entries)
        DailyTempo(
          day,
          dayRuns.map(bpm).reduce(math.max),
          dayRuns.map(bpm).reduce(math.min),
          dayRuns.length,
        ),
    ];
  }
}

/// A line chart of average accuracy per practice day, on a fixed 0-100%
/// scale.
class AccuracyByDayChart extends StatelessWidget {
  final List<DailyAccuracy> days;

  const AccuracyByDayChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    return _DailyLineChart(
      key: const Key('accuracy_chart'),
      points: [for (final day in days) _DailyPoint(day.day, day.averageAccuracy)],
      minY: 0,
      maxY: 1,
      gridValues: const [0, 0.5, 1],
      axisLabel: accuracyText,
      valueLabel: accuracyText,
      tooltip: (index) {
        final day = days[index];
        return '${shortDate(day.day)}: ${accuracyText(day.averageAccuracy)} '
            '(${day.runCount} ${day.runCount == 1 ? 'run' : 'runs'})';
      },
    );
  }
}

/// A line chart of the fastest tempo played each practice day, with the
/// track's target tempo (when known) as a dashed reference line -- so the
/// climb toward it is visible.
class TempoByDayChart extends StatelessWidget {
  final List<DailyTempo> days;
  final int? targetBpm;

  const TempoByDayChart({super.key, required this.days, this.targetBpm});

  @override
  Widget build(BuildContext context) {
    final values = [for (final day in days) day.topBpm, ?targetBpm];
    // A scale of whole 10s around the tempos shown, with a little room.
    final low = ((values.reduce(math.min) - 5) / 10).floor() * 10.0;
    final high = ((values.reduce(math.max) + 5) / 10).ceil() * 10.0;
    String bpm(double value) => '${value.round()}';
    return _DailyLineChart(
      key: const Key('tempo_chart'),
      points: [for (final day in days) _DailyPoint(day.day, day.topBpm.toDouble())],
      minY: low,
      maxY: high,
      gridValues: [low, ((low + high) / 2 / 5).round() * 5.0, high],
      axisLabel: bpm,
      valueLabel: (value) => '${value.round()} BPM',
      referenceValue: targetBpm?.toDouble(),
      referenceLabel: targetBpm == null ? null : 'Target $targetBpm',
      tooltip: (index) {
        final day = days[index];
        final range = day.slowestBpm == day.topBpm ? '' : ', ${day.slowestBpm}–${day.topBpm}';
        return '${shortDate(day.day)}: top ${day.topBpm} BPM '
            '(${day.runCount} ${day.runCount == 1 ? 'run' : 'runs'}$range)';
      },
    );
  }
}

class _DailyPoint {
  final DateTime day;
  final double value;

  const _DailyPoint(this.day, this.value);
}

/// One line of values, one point per practice day, evenly spaced and
/// oldest on the left. The latest day's value is labelled; tapping a point
/// shows [tooltip] for it. Built after the dataviz guidance for a single
/// series: a 2px line in the theme's primary colour, markers ringed in the
/// surface colour, a recessive grid, no legend (the title names it).
class _DailyLineChart extends StatefulWidget {
  final List<_DailyPoint> points;
  final double minY;
  final double maxY;
  final List<double> gridValues;
  final String Function(double value) axisLabel;
  final String Function(double value) valueLabel;
  final String Function(int index) tooltip;

  /// A dashed horizontal line marking a value to aim for, if any.
  final double? referenceValue;
  final String? referenceLabel;

  const _DailyLineChart({
    super.key,
    required this.points,
    required this.minY,
    required this.maxY,
    required this.gridValues,
    required this.axisLabel,
    required this.valueLabel,
    required this.tooltip,
    this.referenceValue,
    this.referenceLabel,
  });

  @override
  State<_DailyLineChart> createState() => _DailyLineChartState();
}

class _DailyLineChartState extends State<_DailyLineChart> {
  int? _tapped;

  static const double _height = 180;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _ChartGeometry(
          Size(constraints.maxWidth, _height),
          widget.points.length,
          widget.minY,
          widget.maxY,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Generous hit area: the nearest point to the tap, anywhere.
          onTapDown: (details) => setState(() {
            if (widget.points.isEmpty) return;
            final nearest = geometry.nearestIndex(details.localPosition.dx);
            _tapped = nearest == _tapped ? null : nearest;
          }),
          child: CustomPaint(
            size: Size(constraints.maxWidth, _height),
            painter: _DailyLineChartPainter(
              chart: widget,
              geometry: geometry,
              tapped: _tapped,
              line: theme.colorScheme.primary,
              surface: theme.colorScheme.surface,
              ink: theme.colorScheme.onSurface,
              mutedInk: theme.colorScheme.onSurfaceVariant,
              grid: theme.colorScheme.outlineVariant,
              textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}

/// Where things go on the chart. Shared by the painter and the tap
/// handling so they agree.
class _ChartGeometry {
  final Size size;
  final int count;
  final double minY;
  final double maxY;

  _ChartGeometry(this.size, this.count, this.minY, this.maxY);

  static const double left = 40; // room for the axis labels
  static const double right = 28; // room for the last point's label
  static const double top = 22;
  static const double bottom = 24; // room for date labels

  double get plotWidth => size.width - left - right;
  double get plotHeight => size.height - top - bottom;

  double xFor(int index) =>
      count == 1 ? left + plotWidth / 2 : left + plotWidth * index / (count - 1);

  double yFor(double value) {
    final fraction = maxY == minY ? 0.5 : ((value - minY) / (maxY - minY)).clamp(0.0, 1.0);
    return top + plotHeight * (1 - fraction);
  }

  int nearestIndex(double dx) {
    var best = 0;
    for (var index = 1; index < count; index++) {
      if ((xFor(index) - dx).abs() < (xFor(best) - dx).abs()) best = index;
    }
    return best;
  }
}

class _DailyLineChartPainter extends CustomPainter {
  final _DailyLineChart chart;
  final _ChartGeometry geometry;
  final int? tapped;
  final Color line;
  final Color surface;
  final Color ink;
  final Color mutedInk;
  final Color grid;
  final TextStyle textStyle;

  _DailyLineChartPainter({
    required this.chart,
    required this.geometry,
    required this.tapped,
    required this.line,
    required this.surface,
    required this.ink,
    required this.mutedInk,
    required this.grid,
    required this.textStyle,
  });

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    Color? color,
    bool alignRight = false,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: color ?? mutedInk),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? anchor.dx - painter.width
        : center
        ? anchor.dx - painter.width / 2
        : anchor.dx;
    painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final points = chart.points;
    final plotRight = size.width - _ChartGeometry.right;

    // Recessive grid.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final level in chart.gridValues) {
      final y = g.yFor(level);
      canvas.drawLine(Offset(_ChartGeometry.left, y), Offset(plotRight, y), gridPaint);
      _text(canvas, chart.axisLabel(level), Offset(_ChartGeometry.left - 6, y), alignRight: true);
    }

    // The value to aim for: a dashed line, labelled at its right end.
    final reference = chart.referenceValue;
    if (reference != null) {
      final y = g.yFor(reference);
      final dash = Paint()
        ..color = mutedInk
        ..strokeWidth = 1.5;
      for (var x = _ChartGeometry.left; x < plotRight; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, plotRight), y), dash);
      }
      if (chart.referenceLabel case final label?) {
        _text(canvas, label, Offset(plotRight, y - 8), alignRight: true);
      }
    }

    if (points.isEmpty) return;

    // Date labels: the first and last day (and the middle one when there's
    // room), so they never collide.
    final labelled = <int>{0, points.length - 1, if (points.length >= 5) points.length ~/ 2};
    for (final index in labelled) {
      _text(
        canvas,
        shortDate(points[index].day),
        Offset(g.xFor(index), size.height - _ChartGeometry.bottom / 2),
        center: true,
      );
    }

    final offsets = [
      for (var i = 0; i < points.length; i++) Offset(g.xFor(i), g.yFor(points[i].value)),
    ];
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // Markers, ringed in the surface colour so they read over the line.
    for (final point in offsets) {
      canvas.drawCircle(point, 6, Paint()..color = surface);
      canvas.drawCircle(point, 4, Paint()..color = line);
    }

    // Direct label on the latest day only.
    _text(
      canvas,
      chart.valueLabel(points.last.value),
      offsets.last + const Offset(0, -14),
      color: ink,
      center: true,
    );

    final index = tapped;
    if (index != null && index < points.length) {
      final point = offsets[index];
      final painter = TextPainter(
        text: TextSpan(
          text: chart.tooltip(index),
          style: textStyle.copyWith(color: surface),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
      final width = painter.width + padding.horizontal;
      final height = painter.height + padding.vertical;
      final left = (point.dx - width / 2).clamp(0.0, size.width - width);
      final top = point.dy - height - 12 < 0 ? point.dy + 12 : point.dy - height - 12;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, top, width, height), const Radius.circular(6)),
        Paint()..color = ink,
      );
      painter.paint(canvas, Offset(left + padding.left, top + padding.top));
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_DailyLineChartPainter oldDelegate) =>
      oldDelegate.chart != chart ||
      oldDelegate.tapped != tapped ||
      oldDelegate.geometry.size != geometry.size;
}
