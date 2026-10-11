import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/practice_history.dart';
import '../services/practice_schedule.dart';
import '../services/score_storage.dart';
import '../services/track_sections.dart';
import '../widgets/schedule_practice_dialog.dart';
import '../widgets/schedule_scope.dart';
import '../widgets/section_dialog.dart';
import 'calibration_screen.dart';
import 'history_screen.dart';
import 'mic_test_screen.dart';
import 'practice_screen.dart';
import 'score_editor_screen.dart';
import 'settings_screen.dart';

class ScoreListScreen extends StatefulWidget {
  /// Where scores are kept. Replaceable so tests can use an in-memory one.
  final ScoreStorage? storage;

  /// Where practice runs are kept; replaceable likewise.
  final PracticeHistoryStore? historyStore;

  /// Where tracks' sections are kept; replaceable likewise.
  final SectionStore? sectionStore;

  const ScoreListScreen({super.key, this.storage, this.historyStore, this.sectionStore});

  @override
  State<ScoreListScreen> createState() => _ScoreListScreenState();
}

class _ScoreListScreenState extends State<ScoreListScreen> {
  late final ScoreStorage _storage = widget.storage ?? ScoreStorage();
  late final PracticeHistoryStore _history = widget.historyStore ?? FilePracticeHistoryStore();
  late final TrackSections _sections = TrackSections(widget.sectionStore ?? FileSectionStore());
  late Future<List<ScoreFileInfo>> _scoresFuture;

  /// Each track's sections, by track; filled in shortly after the tracks.
  Map<String, List<TrackSection>> _sectionsByTrack = const {};

  @override
  void initState() {
    super.initState();
    _scoresFuture = _storage.listScores();
    _loadSections();
  }

  void _refresh() {
    setState(() {
      _scoresFuture = _storage.listScores();
    });
    _loadSections();
  }

  Future<void> _loadSections() async {
    try {
      final all = await _sections.store.load();
      final byTrack = <String, List<TrackSection>>{};
      for (final section in all) {
        (byTrack[section.trackId] ??= []).add(section);
      }
      for (final list in byTrack.values) {
        list.sort((a, b) {
          final byStart = a.firstMeasure.compareTo(b.firstMeasure);
          return byStart != 0 ? byStart : a.lastMeasure.compareTo(b.lastMeasure);
        });
      }
      if (mounted) setState(() => _sectionsByTrack = byTrack);
    } catch (e) {
      debugPrint('Could not load sections: $e');
    }
  }

  /// Makes a new section of a track: a named range of its measures that
  /// can be practised on its own, linked to the track.
  Future<void> _newSection(ScoreFileInfo info) async {
    final track = await _storage.load(info.fileName);
    if (!mounted) return;
    final count = (_sectionsByTrack[info.fileName]?.length ?? 0) + 1;
    final choice = await showSectionDialog(
      context,
      title: 'New section of ${info.title}',
      measureCount: track.measures.length,
      name: 'Section $count',
      lastMeasure: track.measures.length >= 4 ? 3 : track.measures.length - 1,
    );
    if (choice == null) return;
    await _sections.put(
      TrackSection(
        id: '${clock.now().microsecondsSinceEpoch}',
        trackId: info.fileName,
        name: choice.name,
        firstMeasure: choice.firstMeasure,
        lastMeasure: choice.lastMeasure,
      ),
    );
    await _loadSections();
  }

  Future<void> _editSection(TrackSection section, ScoreFileInfo info) async {
    final track = await _storage.load(info.fileName);
    if (!mounted) return;
    final choice = await showSectionDialog(
      context,
      title: 'Edit section',
      measureCount: track.measures.length,
      name: section.name,
      firstMeasure: section.firstMeasure,
      lastMeasure: section.lastMeasure,
    );
    if (choice == null) return;
    await _sections.put(
      section.copyWith(
        name: choice.name,
        firstMeasure: choice.firstMeasure,
        lastMeasure: choice.lastMeasure,
      ),
    );
    await _loadSections();
  }

  Future<void> _deleteSection(TrackSection section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the section "${section.name}"?'),
        content: const Text('The track itself, and its practice history, are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('delete_section_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sections.delete(section);
    await _loadSections();
  }

  /// Practises just a section: its measures, taken from the mother track as
  /// it is now, with runs saved to the mother track's history.
  Future<void> _practiceSection(TrackSection section, ScoreFileInfo info) async {
    final track = await _storage.load(info.fileName);
    if (!mounted) return;
    final score = section.extractFrom(track);
    if (score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${info.title} no longer has measures '
              '${section.firstMeasure + 1}–${section.lastMeasure + 1}. Edit the section to pick '
              'measures it has.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          score: score,
          scoreId: info.fileName,
          historyStore: _history,
          section: section,
        ),
      ),
    );
  }

  Future<void> _createNew() async {
    final title = await _promptForTitle();
    if (title == null || title.isEmpty) return;
    if (!mounted) return;

    final fileName = _sanitizeFileName(title);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScoreEditorScreen(
          fileName: fileName,
          initialScore: RhythmScore.empty(title: title),
          storage: _storage,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _open(String fileName) async {
    final score = await _storage.load(fileName);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScoreEditorScreen(
          fileName: fileName,
          initialScore: score,
          sections: _sections,
          storage: _storage,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openPractice(String fileName) async {
    final score = await _storage.load(fileName);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeScreen(score: score, scoreId: fileName, historyStore: _history),
      ),
    );
  }

  Future<String?> _promptForTitle({
    String dialogTitle = 'New Rhythm',
    String confirmLabel = 'Create',
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dialogTitle),
        content: TextField(
          key: const Key('title_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('title_confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Changes the title saved inside the score. The file keeps its name (and
  /// so its ID): the list shows the title from inside the file.
  Future<void> _rename(ScoreFileInfo info) async {
    final title = await _promptForTitle(
      dialogTitle: 'Rename',
      confirmLabel: 'Rename',
      initial: info.title,
    );
    if (title == null || title.isEmpty || title == info.title) return;
    final score = await _storage.load(info.fileName);
    await _storage.save(info.fileName, score.copyWith(title: title));
    if (mounted) _refresh();
  }

  /// Asks how practice of this track should repeat -- every day, on chosen
  /// days each week, or once -- and when, then schedules the reminders.
  /// One schedule per track: a new one replaces the old.
  Future<void> _schedule(ScoreFileInfo info) async {
    final schedule = ScheduleScope.of(context);
    final choice = await showSchedulePracticeDialog(
      context,
      trackTitle: info.title,
      current: schedule.forTrack(info.fileName),
    );
    if (choice == null || !mounted) return;

    final outcome = await schedule.add(
      scoreId: info.fileName,
      trackTitle: info.title,
      repeat: choice.repeat,
      hour: choice.time.hour,
      minute: choice.time.minute,
      weekdays: choice.weekdays,
      onceOn: choice.date,
      body: 'Your practice session for ${info.title} is now.',
    );
    final scheduled = schedule.forTrack(info.fileName);
    final description = scheduled == null ? '' : describeSchedule(scheduled);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case ScheduleOutcome.scheduled:
        messenger.showSnackBar(SnackBar(content: Text('Practice scheduled: $description')));
      case ScheduleOutcome.scheduledApproximately:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Practice scheduled: $description. '
                'Reminders may come a few minutes late.'),
            action: SnackBarAction(label: 'Be exact', onPressed: schedule.requestExactTiming),
          ),
        );
      case ScheduleOutcome.noDaysChosen:
        messenger.showSnackBar(const SnackBar(content: Text('Pick at least one day.')));
      case ScheduleOutcome.inThePast:
        messenger.showSnackBar(
          const SnackBar(content: Text('Pick a time that hasn\'t passed yet.')),
        );
      case ScheduleOutcome.notificationsNotAllowed:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Notifications are off for MyTrak. Allow them in the phone\'s settings '
                'to get practice reminders.'),
          ),
        );
    }
  }

  Future<void> _unschedule(ScheduledPractice practice) async {
    await ScheduleScope.of(context).cancel(practice);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Scheduled practice cancelled')));
  }

  Future<void> _delete(ScoreFileInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${info.title}"?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('delete_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.delete(info.fileName);
    // The track's practice history goes with it -- in the background: the
    // list doesn't need to wait for its recordings to be removed.
    unawaited(_history.deleteAllFor(info.fileName).catchError((Object e) {
      debugPrint('Could not delete the practice history of ${info.fileName}: $e');
    }));
    unawaited(_sections.deleteAllFor(info.fileName).then((_) => _loadSections()).catchError(
      (Object e) => debugPrint('Could not delete the sections of ${info.fileName}: $e'),
    ));
    if (!mounted) return;
    unawaited(ScheduleScope.of(context).cancelAllFor(info.fileName));
    if (mounted) _refresh();
  }

  /// Shows the details kept out of the list itself: the score's ID (the
  /// number that keeps same-titled scores apart) and what it was made from.
  Future<void> _showMoreInfo(ScoreFileInfo score) {
    final created = score.createdAt;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(score.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${score.id ?? 'none'}', key: const Key('more_info_id')),
            if (created != null) ...[
              const SizedBox(height: 8),
              Text('Created: ${_formatDateTime(created)}'),
            ],
            const SizedBox(height: 8),
            Text('File: ${score.fileName}.mid'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _sanitizeFileName(String title) {
    final sanitized = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return '${sanitized}_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyTrak'),
        actions: [
          // Temporary entry point for the Milestone 4 hit-detection spike.
          IconButton(
            key: const Key('mic_test_button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MicTestScreen()),
            ),
            icon: const Icon(Icons.mic_none),
            tooltip: 'Mic test',
          ),
          IconButton(
            key: const Key('calibration_button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CalibrationScreen()),
            ),
            icon: const Icon(Icons.tune),
            tooltip: 'Calibration',
          ),
          IconButton(
            key: const Key('history_button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(storage: _storage, historyStore: _history),
              ),
            ),
            icon: const Icon(Icons.history),
            tooltip: 'Practice history',
          ),
          IconButton(
            key: const Key('settings_button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: FutureBuilder<List<ScoreFileInfo>>(
        future: _scoresFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final scores = snapshot.data!;
          if (scores.isEmpty) {
            return const Center(child: Text('No saved rhythms yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: scores.length,
            itemBuilder: (context, index) {
              final score = scores[index];
              final name = score.fileName;
              final scheduled = ScheduleScope.of(context).forTrack(name);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              score.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          PopupMenuButton<_TrackAction>(
                            key: Key('score_menu_$name'),
                            tooltip: 'More actions',
                            onSelected: (action) {
                              switch (action) {
                                case _TrackAction.schedule:
                                  _schedule(score);
                                case _TrackAction.unschedule:
                                  _unschedule(scheduled!);
                                case _TrackAction.newSection:
                                  _newSection(score);
                                case _TrackAction.rename:
                                  _rename(score);
                                case _TrackAction.delete:
                                  _delete(score);
                                case _TrackAction.moreInfo:
                                  _showMoreInfo(score);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                key: const Key('score_menu_schedule'),
                                value: _TrackAction.schedule,
                                child: ListTile(
                                  leading: const Icon(Icons.alarm_add),
                                  title: Text(
                                    scheduled == null ? 'Schedule practice' : 'Reschedule practice',
                                  ),
                                ),
                              ),
                              if (scheduled != null)
                                const PopupMenuItem(
                                  key: Key('score_menu_unschedule'),
                                  value: _TrackAction.unschedule,
                                  child: ListTile(
                                    leading: Icon(Icons.alarm_off),
                                    title: Text('Cancel scheduled practice'),
                                  ),
                                ),
                              const PopupMenuItem(
                                key: Key('score_menu_new_section'),
                                value: _TrackAction.newSection,
                                child: ListTile(
                                  leading: Icon(Icons.content_cut),
                                  title: Text('New section...'),
                                ),
                              ),
                              const PopupMenuItem(
                                key: Key('score_menu_rename'),
                                value: _TrackAction.rename,
                                child: ListTile(
                                  leading: Icon(Icons.drive_file_rename_outline),
                                  title: Text('Rename'),
                                ),
                              ),
                              const PopupMenuItem(
                                key: Key('score_menu_delete'),
                                value: _TrackAction.delete,
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete'),
                                ),
                              ),
                              const PopupMenuItem(
                                key: Key('score_menu_more_info'),
                                value: _TrackAction.moreInfo,
                                child: ListTile(
                                  leading: Icon(Icons.info_outline),
                                  title: Text('More info...'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: Key('edit_$name'),
                              onPressed: () => _open(name),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: Key('practice_$name'),
                              onPressed: () => _openPractice(name),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Practice'),
                            ),
                          ),
                        ],
                      ),
                      for (final section in _sectionsByTrack[name] ?? const <TrackSection>[])
                        _SectionRow(
                          key: Key('section_${section.id}'),
                          section: section,
                          onPractice: () => _practiceSection(section, score),
                          onEdit: () => _editSection(section, score),
                          onDelete: () => _deleteSection(section),
                        ),
                      if (scheduled case final practice?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.alarm,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Practice scheduled: ${describeSchedule(practice)}',
                                  key: Key('score_scheduled_$name'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: _createNew,
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _TrackAction { schedule, unschedule, newSection, rename, delete, moreInfo }

/// One section listed under its track on the main menu: its name and range,
/// a button to practise it, and a menu to edit or delete it.
class _SectionRow extends StatelessWidget {
  final TrackSection section;
  final VoidCallback onPractice;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SectionRow({
    super.key,
    required this.section,
    required this.onPractice,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 8),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: section.name, style: textTheme.bodyMedium),
                  TextSpan(text: '  ${section.rangeLabel}', style: textTheme.bodySmall),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            key: Key('section_practice_${section.id}'),
            onPressed: onPractice,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Practice'),
          ),
          PopupMenuButton<bool>(
            key: Key('section_menu_${section.id}'),
            tooltip: 'Section actions',
            onSelected: (edit) => edit ? onEdit() : onDelete(),
            itemBuilder: (context) => const [
              PopupMenuItem(
                key: Key('section_menu_edit'),
                value: true,
                child: ListTile(leading: Icon(Icons.tune), title: Text('Edit section')),
              ),
              PopupMenuItem(
                key: Key('section_menu_delete'),
                value: false,
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete section')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
