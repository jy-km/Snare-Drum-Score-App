import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/dynamics_check.dart';
import '../services/hit_judge.dart';
import '../services/run_review.dart';
import 'app_theme.dart';
import 'judgement_style.dart';

/// The run's recording drawn as a sound wave, from just before measure 1 to
/// just after the end, with what to read it against: a small mark over the
/// wave where each note was due, a tick under it in its judgement's colour
/// where each hit was heard (a cross for a note not played), the measures,
/// and the replay's playhead.
///
/// The wave is scaled to the run's loudest moment, so a quiet run still
/// fills the height. Zoom in (up to [maxZoom] times) to see single strokes,
/// and scroll sideways; zoomed in, it keeps the playhead in view. Tapping
/// near a note says how it went -- its timing and how loud it was -- and
/// [onSelect] hears about it.
class WaveformView extends StatefulWidget {
  final RunReview review;

  /// Where the replay is, in seconds from the start of the count-in, or
  /// null when it isn't playing.
  final double? playheadSeconds;

  final ValueChanged<JudgedHit>? onSelect;

  const WaveformView({super.key, required this.review, this.playheadSeconds, this.onSelect});

  static const double waveHeight = 120;
  static const double maxZoom = 16;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  final _scroll = ScrollController();
  double _zoom = 1;
  JudgedHit? _selected;

  static const double _markRowHeight = 14;
  static const double _heardRowHeight = 12;
  static const double _axisHeight = 18;

  /// Each envelope column covers this long: fine enough for the closest
  /// zoom on a phone.
  static const double _columnSeconds = 0.0025;

  RunReview get _review => widget.review;

  late final double _fromSeconds = math.max(
    0,
    _review.layout.starts[1] * _review.secondsPerUnit - 0.25,
  );
  late final double _toSeconds = math.min(
    _review.audioSeconds,
    _review.layout.starts.last * _review.secondsPerUnit + 0.5,
  );

  /// The loudest and quietest sample in each column, from [_fromSeconds],
  /// as fractions of the run's loudest.
  late final (Float32List, Float32List) _envelope = () {
    final audio = _review.audio;
    final rate = _review.sampleRate;
    final perColumn = math.max(1, (_columnSeconds * rate).round());
    final from = (_fromSeconds * rate).round().clamp(0, audio.length);
    final to = (_toSeconds * rate).round().clamp(from, audio.length);
    final count = ((to - from) / perColumn).ceil();
    final lows = Float32List(count);
    final highs = Float32List(count);
    var peak = 1;
    for (var i = from; i < to; i++) {
      final sample = audio[i];
      if (sample.abs() > peak) peak = sample.abs();
      final column = (i - from) ~/ perColumn;
      if (sample < lows[column] * 32768) lows[column] = sample / 32768;
      if (sample > highs[column] * 32768) highs[column] = sample / 32768;
    }
    final scale = 32768 / peak;
    for (var column = 0; column < count; column++) {
      lows[column] *= scale;
      highs[column] *= scale;
    }
    return (lows, highs);
  }();

  /// The notes judged, in note order.
  late final List<JudgedHit> _hits = [
    for (final hit in _review.judgements)
      if (hit.noteIndex != null) hit,
  ]..sort((a, b) => a.noteIndex!.compareTo(b.noteIndex!));

  double _pixelsPerSecond(double viewWidth) => viewWidth / (_toSeconds - _fromSeconds) * _zoom;

  double _x(double seconds, double viewWidth) =>
      (seconds - _fromSeconds) * _pixelsPerSecond(viewWidth);

  @override
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final playhead = widget.playheadSeconds;
    if (playhead == null || _zoom == 1 || !_scroll.hasClients) return;
    // Zoomed in, keep the playhead on screen: once it runs off the right
    // edge, turn the page so it's near the left again.
    final position = _scroll.position;
    final x = _x(playhead, position.viewportDimension);
    if (x < position.pixels || x > position.pixels + position.viewportDimension) {
      _scroll.jumpTo((x - position.viewportDimension * 0.1).clamp(0.0, position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Zooms by [factor], keeping what's in the middle of the view there.
  void _zoomBy(double factor) {
    final zoom = (_zoom * factor).clamp(1.0, WaveformView.maxZoom);
    if (zoom == _zoom) return;
    final position = _scroll.hasClients ? _scroll.position : null;
    final middle = position == null
        ? 0.0
        : (position.pixels + position.viewportDimension / 2) / _zoom;
    setState(() => _zoom = zoom);
    if (position == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _scroll.jumpTo((middle * _zoom - p.viewportDimension / 2).clamp(0.0, p.maxScrollExtent));
    });
  }

  /// The note nearest a tap at [x] (across the whole wave), if any is close
  /// enough to mean it.
  JudgedHit? _hitAt(double x, double viewWidth) {
    JudgedHit? nearest;
    var best = 24.0; // a finger's width either side
    for (final hit in _hits) {
      final distance = (_x(_review.noteTimes[hit.noteIndex!], viewWidth) - x).abs();
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
    final time = hit.hitTimeSeconds;
    if (offset == null || time == null) return '$where: not played';
    final side = offset.abs() < 0.0005 ? 'on time' : (offset < 0 ? 'early' : 'late');
    final loudness = DynamicsCheck.hitLoudnessDb(_review.audio, _review.sampleRate, time);
    return '$where: ${judgementLabelWithDirection(hit)}, ${offsetText(offset)} ($side)'
        '${loudness == null ? '' : ', ${loudness.round()} dB'}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selected == null
                    ? 'Tap near a note to see its timing and how loud it was.'
                    : _caption(selected),
                key: const Key('waveform_caption'),
                style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
              ),
            ),
            IconButton(
              key: const Key('waveform_zoom_out'),
              tooltip: 'Zoom out',
              onPressed: _zoom > 1 ? () => _zoomBy(0.5) : null,
              icon: const Icon(Icons.zoom_out),
            ),
            SizedBox(
              width: 32,
              child: Text(
                '${_zoom.round()}×',
                key: const Key('waveform_zoom'),
                textAlign: TextAlign.center,
                style: textTheme.labelMedium,
              ),
            ),
            IconButton(
              key: const Key('waveform_zoom_in'),
              tooltip: 'Zoom in',
              onPressed: _zoom < WaveformView.maxZoom ? () => _zoomBy(2) : null,
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewWidth = constraints.maxWidth;
            final width = viewWidth * _zoom;
            return SingleChildScrollView(
              key: const Key('waveform_scroll'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final hit = _hitAt(details.localPosition.dx, viewWidth);
                  if (hit != null) _select(hit);
                },
                child: CustomPaint(
                  key: const Key('waveform_paint'),
                  size: Size(
                    width,
                    _markRowHeight + WaveformView.waveHeight + _heardRowHeight + _axisHeight,
                  ),
                  painter: _WaveformPainter(
                    state: this,
                    viewWidth: viewWidth,
                    palette: palette,
                    labelStyle: (textTheme.labelSmall ?? const TextStyle()).copyWith(
                      color: palette.mutedInk,
                    ),
                    zoom: _zoom,
                    selected: selected,
                    playheadSeconds: widget.playheadSeconds,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        _Key(palette: palette),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final _WaveformViewState state;
  final double viewWidth;
  final AppPalette palette;
  final TextStyle labelStyle;
  final double zoom;
  final JudgedHit? selected;
  final double? playheadSeconds;

  _WaveformPainter({
    required this.state,
    required this.viewWidth,
    required this.palette,
    required this.labelStyle,
    required this.zoom,
    required this.selected,
    required this.playheadSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const markRow = _WaveformViewState._markRowHeight;
    const top = markRow;
    const height = WaveformView.waveHeight;
    const middle = top + height / 2;
    final review = state._review;
    double x(double seconds) => state._x(seconds, viewWidth);
    final hairline = Paint()
      ..color = palette.rule
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, height),
      Paint()..color = palette.ink.withValues(alpha: 0.03),
    );

    const heardRow = top + height;
    const axisRow = heardRow + _WaveformViewState._heardRowHeight;

    // Measures: a line where each starts, its number just after it (where
    // it's still on screen zoomed in).
    final layout = review.layout;
    for (var measure = 1; measure <= layout.measureCount; measure++) {
      final at = x(layout.starts[measure] * review.secondsPerUnit);
      canvas.drawLine(Offset(at, top), Offset(at, axisRow), hairline);
      if (measure == layout.measureCount) break;
      _label(
        canvas,
        '${measure + layout.firstMeasureNumber - 1}',
        Offset(at + 4, axisRow + _WaveformViewState._axisHeight / 2),
      );
    }
    canvas.drawLine(Offset(0, middle), Offset(size.width, middle), hairline);

    // Where each hit was heard, faintly behind the wave so as not to hide it.
    for (final hit in state._hits) {
      final heard = hit.hitTimeSeconds;
      if (heard == null) continue;
      canvas.drawLine(
        Offset(x(heard), top),
        Offset(x(heard), heardRow),
        Paint()
          ..color = judgementColor(hit.judgement, palette).withValues(alpha: 0.3)
          ..strokeWidth = 1.5,
      );
    }

    // The wave: a line from the quietest to the loudest sample of each
    // pixel's stretch.
    final (lows, highs) = state._envelope;
    final columnsPerPixel =
        1 / (state._pixelsPerSecond(viewWidth) * _WaveformViewState._columnSeconds);
    final wave = Paint()
      ..color = palette.ink.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    for (var pixel = 0; pixel < size.width; pixel++) {
      final first = (pixel * columnsPerPixel).floor();
      if (first >= lows.length) break;
      final last = math.min(lows.length, ((pixel + 1) * columnsPerPixel).ceil());
      var low = 0.0;
      var high = 0.0;
      for (var column = first; column < math.max(first + 1, last); column++) {
        if (lows[column] < low) low = lows[column];
        if (highs[column] > high) high = highs[column];
      }
      canvas.drawLine(
        Offset(pixel + 0.5, middle - high * height / 2),
        // At least a pixel tall, so silence still shows as a line.
        Offset(pixel + 0.5, middle - low * height / 2 + 1),
        wave,
      );
    }

    // Where each note was due (a mark over the wave) and where its hit was
    // heard (a tick under it, in its judgement's colour) -- or, not played,
    // a cross under it. Due and heard lining up is a hit on time.
    final due = Paint()..color = palette.mutedInk;
    for (final hit in state._hits) {
      final noteX = x(review.noteTimes[hit.noteIndex!]);
      final color = judgementColor(hit.judgement, palette);
      final isSelected = identical(hit, selected);
      canvas.drawPath(
        Path()
          ..moveTo(noteX - 4, 2)
          ..lineTo(noteX + 4, 2)
          ..lineTo(noteX, markRow - 3)
          ..close(),
        isSelected ? (Paint()..color = palette.ink) : due,
      );
      final heard = hit.hitTimeSeconds;
      if (heard == null) {
        const arm = 4.0;
        const middleOfRow = heardRow + _WaveformViewState._heardRowHeight / 2;
        final cross = Paint()
          ..color = color
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(noteX - arm, middleOfRow - arm),
          Offset(noteX + arm, middleOfRow + arm),
          cross,
        );
        canvas.drawLine(
          Offset(noteX - arm, middleOfRow + arm),
          Offset(noteX + arm, middleOfRow - arm),
          cross,
        );
        continue;
      }
      canvas.drawLine(
        Offset(x(heard), heardRow + 1),
        Offset(x(heard), heardRow + _WaveformViewState._heardRowHeight - 1),
        Paint()
          ..color = color
          ..strokeWidth = isSelected ? 4 : 2.5,
      );
    }

    final playhead = playheadSeconds;
    if (playhead != null) {
      canvas.drawLine(
        Offset(x(playhead), 0),
        Offset(x(playhead), top + height),
        Paint()
          ..color = palette.accent
          ..strokeWidth = 2,
      );
    }
  }

  /// [text] with its left edge at [at], centred on it up and down.
  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(0, painter.height / 2));
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.zoom != zoom ||
      oldDelegate.viewWidth != viewWidth ||
      oldDelegate.selected != selected ||
      oldDelegate.playheadSeconds != playheadSeconds ||
      oldDelegate.palette != palette;
}

/// What the marks are: due, heard (in the judgement's colour), not played.
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_drop_down, size: 18, color: palette.mutedInk),
            Text('note due', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2, height: 12, color: palette.great),
            const SizedBox(width: 5),
            // Wraps rather than running off a narrow screen.
            Flexible(child: Text("hit heard, in its judgement's colour", style: style)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 12, color: palette.miss),
            const SizedBox(width: 4),
            Text('not played', style: style),
          ],
        ),
        Text(
          'dB: how loud, 0 being the loudest a recording can be',
          style: style?.copyWith(color: palette.mutedInk),
        ),
      ],
    );
  }
}
