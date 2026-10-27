import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/dynamics_check.dart';
import '../services/timeline_layout.dart';
import 'app_theme.dart';
import 'staff_notation_view.dart';

/// "3 of 4 dynamics as marked", or null when there's nothing judged.
String? dynamicsSummary(DynamicsCheck check) {
  if (check.judged == 0) return null;
  return '${check.met} of ${check.judged} dynamics as marked';
}

/// How a run's dynamics went: each change of marking and each crescendo or
/// decrescendo, with whether it was played as marked and by how much. The
/// levels are the player's own -- louder or softer than each other -- not
/// measured against any fixed loudness.
class DynamicsResults extends StatelessWidget {
  final DynamicsCheck check;
  final TimelineLayout layout;

  const DynamicsResults({super.key, required this.check, required this.layout});

  String _measureOf(int note) => 'measure ${layout.noteLocations[note].$1}';

  String _where(int first, int last) {
    final from = layout.noteLocations[first];
    final to = layout.noteLocations[last];
    return from.$1 == to.$1
        ? 'measure ${from.$1}, notes ${from.$2}-${to.$2}'
        : 'measure ${from.$1} note ${from.$2} to measure ${to.$1} note ${to.$2}';
  }

  static String _db(double db) => '${db.abs().toStringAsFixed(db.abs() < 10 ? 1 : 0)} dB';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = AppPalette.of(context);
    final summary = dynamicsSummary(check);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null)
          Text(summary, key: const Key('dynamics_summary'), style: textTheme.bodyMedium),
        for (final (index, change) in check.changes.indexed)
          _ResultLine(
            key: Key('dynamics_change_$index'),
            met: change.met,
            palette: palette,
            text: TextSpan(
              children: [
                _mark(change.from.mark),
                const TextSpan(text: ' to '),
                _mark(change.to.mark),
                TextSpan(text: ', ${_measureOf(change.to.firstNote)}: '),
                TextSpan(text: _changeText(change)),
              ],
            ),
          ),
        for (final (index, hairpin) in check.hairpins.indexed)
          _ResultLine(
            key: Key('dynamics_hairpin_$index'),
            met: hairpin.met,
            palette: palette,
            text: TextSpan(
              text:
                  '${hairpin.span.kind == Hairpin.crescendo ? 'Crescendo' : 'Decrescendo'}, '
                  '${_where(hairpin.span.firstNote, hairpin.span.lastNote)}: '
                  '${_hairpinText(hairpin)}',
            ),
          ),
      ],
    );
  }

  static String _changeText(DynamicChange change) {
    final difference = change.differenceDb;
    if (difference == null) return 'not enough notes played to tell';
    final asked = change.louder ? 'louder' : 'softer';
    if (change.met == true) return '${_db(difference)} $asked';
    if (difference.abs() < DynamicsCheck.minChangeDb) return 'no real change (should be $asked)';
    return '${_db(difference)} ${difference > 0 ? 'louder' : 'softer'} (should be $asked)';
  }

  static String _hairpinText(HairpinCheck hairpin) {
    final change = hairpin.changeDb;
    if (change == null) return 'not enough notes played to tell';
    final asked = hairpin.span.kind == Hairpin.crescendo ? 'louder' : 'softer';
    if (hairpin.met == true) return '${_db(change)} $asked by the end';
    if (change.abs() < DynamicsCheck.minChangeDb) return 'stayed level (should get $asked)';
    return 'got ${change > 0 ? 'louder' : 'softer'} by ${_db(change)} (should get $asked)';
  }

  static InlineSpan _mark(DynamicMark mark) => TextSpan(
    text: StaffNotationView.dynamicGlyph(mark),
    semanticsLabel: mark.name,
    style: const TextStyle(fontFamily: 'Bravura', fontSize: 22, height: 1),
  );
}

/// One result: a tick for played as marked, a cross for not, a dash for
/// couldn't tell -- and what happened, in ink.
class _ResultLine extends StatelessWidget {
  final bool? met;
  final TextSpan text;
  final AppPalette palette;

  const _ResultLine({super.key, required this.met, required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (met) {
      true => (Icons.check, palette.great, 'As marked'),
      false => (Icons.close, palette.miss, 'Not as marked'),
      null => (Icons.remove, palette.mutedInk, 'Not judged'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color, semanticLabel: label),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(text)),
        ],
      ),
    );
  }
}
