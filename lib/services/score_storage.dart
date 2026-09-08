import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/rhythm_score.dart';
import 'midi_score_codec.dart';

/// Saves/loads [RhythmScore]s as Standard MIDI Files in the app's private
/// documents directory.
class ScoreStorage {
  Future<Directory> _scoresDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/scores');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<String>> listScoreFileNames() async {
    final dir = await _scoresDir();
    final names = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.mid'))
        .map((file) {
      final segment = file.uri.pathSegments.last;
      return segment.substring(0, segment.length - '.mid'.length);
    }).toList();
    names.sort();
    return names;
  }

  Future<void> save(String fileName, RhythmScore score) async {
    final dir = await _scoresDir();
    final file = File('${dir.path}/$fileName.mid');
    await file.writeAsBytes(MidiScoreCodec.encode(score));
  }

  Future<RhythmScore> load(String fileName) async {
    final dir = await _scoresDir();
    final file = File('${dir.path}/$fileName.mid');
    final bytes = await file.readAsBytes();
    return MidiScoreCodec.decode(bytes);
  }

  Future<void> delete(String fileName) async {
    final dir = await _scoresDir();
    final file = File('${dir.path}/$fileName.mid');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
