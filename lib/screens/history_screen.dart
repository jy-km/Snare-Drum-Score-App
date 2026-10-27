import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/hit_judge.dart';
import '../services/practice_history.dart';
import '../services/score_storage.dart';
import '../widgets/accuracy_chart.dart';
import '../widgets/app_theme.dart';
import '../widgets/judgement_style.dart';
import '../widgets/note_dialog.dart';
import 'review_screen.dart';

/// Practice history: the same tracks as the main menu, in the same order
/// and under the same names, each leading to its own history.
class HistoryScreen extends StatefulWidget {
  final ScoreStorage? storage;
  final PracticeHistoryStore? historyStore;

  const HistoryScreen({super.key, this.storage, this.historyStore});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ScoreStorage _storage = widget.storage ?? ScoreStorage();
  late final PracticeHistoryStore _history = widget.historyStore ?? FilePracticeHistoryStore();
  late final Future<List<ScoreFileInfo>> _scores = _storage.listScores();

  Future<void> _openTrack(ScoreFileInfo score) async {
    // The track's tempo is the target line on the tempo chart; the history
    // still opens without it if the track can't be read.
    int? target;
    var targetBeat = TempoBeat.quarter;
    try {
      final track = await _storage.load(score.fileName);
      target = track.tempoBpm;
      targetBeat = track.tempoBeat;
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackHistoryScreen(
          scoreId: score.fileName,
          title: score.title,
          historyStore: _history,
          targetTempoBpm: target,
          tempoBeat: targetBeat,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice History')),
      body: FutureBuilder<List<ScoreFileInfo>>(
        future: _scores,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final scores = snapshot.data!;
          if (scores.isEmpty) {
            return const Center(child: Text('No tracks yet.'));
          }
          return ListView.builder(
            itemCount: scores.length,
            itemBuilder: (context, index) {
              final score = scores[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(score.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: Key('view_history_${score.fileName}'),
                          onPressed: () => _openTrack(score),
                          icon: const Icon(Icons.insights),
                          label: const Text('View Practice History'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One track's practice history: average accuracy by day, the fastest
/// tempo played each day, and every saved run -- each one can be opened in the review screen to see its analysis
/// and hear it again.
class TrackHistoryScreen extends StatefulWidget {
  final String scoreId;
  final String title;
  final PracticeHistoryStore historyStore;

  /// The track's own tempo, drawn as the target on the tempo chart.
  final int? targetTempoBpm;

  /// The note the track's BPM counts; the tempo chart counts every run in
  /// it.
  final TempoBeat tempoBeat;

  const TrackHistoryScreen({
    super.key,
    required this.scoreId,
    required this.title,
    required this.historyStore,
    this.targetTempoBpm,
    this.tempoBeat = TempoBeat.quarter,
  });

  @override
  State<TrackHistoryScreen> createState() => _TrackHistoryScreenState();
}

class _TrackHistoryScreenState extends State<TrackHistoryScreen> {
  late Future<List<PracticeRun>> _runs = widget.historyStore.runsFor(widget.scoreId);

  void _reload() {
    setState(() {
      _runs = widget.historyStore.runsFor(widget.scoreId);
    });
  }

  Future<void> _open(PracticeRun run) async {
    try {
      final review = await widget.historyStore.loadReview(run);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            review: review,
            heading:
                '${_dateTime(run.startedAt)} · ${run.tempoBeat.describe(run.tempoBpm)}'
                '${run.section == null ? '' : ' · ${run.section!.label}'}',
            note: run.note,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open this run: $e')));
    }
  }

  Future<void> _editNote(PracticeRun run) async {
    final note = await showRunNoteDialog(context, initial: run.note);
    if (note == null) return;
    await widget.historyStore.updateNote(run, note);
    _reload();
  }

  Future<void> _delete(PracticeRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the run from ${_dateTime(run.startedAt)}?'),
        content: const Text('Its recording and results will be deleted. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('delete_run_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.historyStore.delete(run);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<PracticeRun>>(
        future: _runs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load the history: ${snapshot.error}'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final runs = snapshot.data!;
          if (runs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No practice recorded for this track yet.\n\n'
                  'Every practice run that is judged (with "Play rhythm sound" off) '
                  'is saved here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final days = DailyAccuracy.fromRuns(runs);
          final tempoDays = DailyTempo.fromRuns(runs, beat: widget.tempoBeat);
          final target = widget.targetTempoBpm;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Average accuracy by day', style: textTheme.titleSmall),
                      Text(
                        '${runs.length} ${runs.length == 1 ? 'run' : 'runs'} on '
                        '${tempoDays.length} ${tempoDays.length == 1 ? 'day' : 'days'}. Tap a point for details.',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      AccuracyByDayChart(days: days),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fastest tempo by day', style: textTheme.titleSmall),
                      Text(
                        target == null
                            ? 'The fastest tempo you played each day.'
                            : 'The fastest tempo you played each day; '
                                  'the dashed line is the track\'s tempo, '
                                  '${widget.tempoBeat.describe(target)}.',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      TempoByDayChart(days: tempoDays, targetBpm: target),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Recordings', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final run in runs)
                _RunCard(
                  key: Key('run_${run.id}'),
                  run: run,
                  onOpen: () => _open(run),
                  onEditNote: () => _editNote(run),
                  onDelete: () => _delete(run),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Oct 7, 14:05".
String _dateTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${shortDate(local)}, ${two(local.hour)}:${two(local.minute)}';
}

String _duration(double seconds) {
  final whole = seconds.round();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

/// One saved run: when, how fast, how well, the player's note, and what
/// can be done with it.
class _RunCard extends StatelessWidget {
  final PracticeRun run;
  final VoidCallback onOpen;
  final VoidCallback onEditNote;
  final VoidCallback onDelete;

  const _RunCard({
    super.key,
    required this.run,
    required this.onOpen,
    required this.onEditNote,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accuracy = run.accuracy;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_dateTime(run.startedAt), style: textTheme.titleSmall)),
                  if (accuracy != null) Text(accuracyText(accuracy), style: textTheme.titleMedium),
                  const SizedBox(width: 8),
                ],
              ),
              if (run.section case final section?)
                Text(
                  'Section: ${section.label}',
                  key: Key('run_section_${run.id}'),
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 2),
              Text(
                '${run.tempoBeat.describe(run.tempoBpm)} · ${_duration(run.durationSeconds)}'
                '${run.timingEstimated ? ' · timing estimated' : ''}',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                children: [
                  for (final judgement in Judgement.values)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: judgementColor(judgement, AppPalette.of(context)),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${judgementLabel(judgement)} ${run.counts[judgement] ?? 0}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                run.note.isEmpty ? 'No note' : run.note,
                key: Key('run_note_${run.id}'),
                style: run.note.isEmpty
                    ? textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)
                    : textTheme.bodyMedium,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    key: Key('open_run_${run.id}'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Review & listen'),
                  ),
                  PopupMenuButton<_RunAction>(
                    key: Key('run_menu_${run.id}'),
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      switch (action) {
                        case _RunAction.note:
                          onEditNote();
                        case _RunAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: const Key('run_menu_note'),
                        value: _RunAction.note,
                        child: ListTile(
                          leading: const Icon(Icons.edit_note),
                          title: Text(run.note.isEmpty ? 'Add note' : 'Edit note'),
                        ),
                      ),
                      const PopupMenuItem(
                        key: Key('run_menu_delete'),
                        value: _RunAction.delete,
                        child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RunAction { note, delete }
