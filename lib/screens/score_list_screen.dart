import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/score_storage.dart';
import 'calibration_screen.dart';
import 'mic_test_screen.dart';
import 'practice_screen.dart';
import 'score_editor_screen.dart';

class ScoreListScreen extends StatefulWidget {
  const ScoreListScreen({super.key});

  @override
  State<ScoreListScreen> createState() => _ScoreListScreenState();
}

class _ScoreListScreenState extends State<ScoreListScreen> {
  final _storage = ScoreStorage();
  late Future<List<ScoreFileInfo>> _scoresFuture;

  @override
  void initState() {
    super.initState();
    _scoresFuture = _storage.listScores();
  }

  void _refresh() {
    setState(() {
      _scoresFuture = _storage.listScores();
    });
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
        builder: (_) => ScoreEditorScreen(fileName: fileName, initialScore: score),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openPractice(String fileName) async {
    final score = await _storage.load(fileName);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PracticeScreen(score: score)),
    );
  }

  Future<String?> _promptForTitle() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Rhythm'),
        content: TextField(
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
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
        title: const Text('MyTempo'),
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(score.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: Key('more_info_$name'),
                          onPressed: () => _showMoreInfo(score),
                          child: const Text('More Info...'),
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
