import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/score_storage.dart';
import 'practice_screen.dart';
import 'score_editor_screen.dart';

class ScoreListScreen extends StatefulWidget {
  const ScoreListScreen({super.key});

  @override
  State<ScoreListScreen> createState() => _ScoreListScreenState();
}

class _ScoreListScreenState extends State<ScoreListScreen> {
  final _storage = ScoreStorage();
  late Future<List<String>> _scoreNamesFuture;

  @override
  void initState() {
    super.initState();
    _scoreNamesFuture = _storage.listScoreFileNames();
  }

  void _refresh() {
    setState(() {
      _scoreNamesFuture = _storage.listScoreFileNames();
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

  String _sanitizeFileName(String title) {
    final sanitized = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return '${sanitized}_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rhythm Scores')),
      body: FutureBuilder<List<String>>(
        future: _scoreNamesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final names = snapshot.data!;
          if (names.isEmpty) {
            return const Center(child: Text('No saved rhythms yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: names.length,
            itemBuilder: (context, index) {
              final name = names[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
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
