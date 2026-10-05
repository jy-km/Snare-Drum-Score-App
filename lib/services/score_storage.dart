import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/rhythm_score.dart';
import 'midi_score_codec.dart';

/// What a saved score's file name says about it. A score is saved as
/// `<title when created>_<creation time in ms since 1970>`: the number keeps
/// two scores with the same title apart, and is the score's ID.
class ScoreFileInfo {
  /// The file's name without its extension -- what [ScoreStorage] loads by.
  final String fileName;

  /// The score's title: the one saved inside the file where that could be
  /// read, otherwise the file name's title part.
  final String title;

  /// The number at the end of the file name, or null for a file not named
  /// by this app's scheme.
  final String? id;

  ScoreFileInfo({required this.fileName, String? title})
      : id = _idPattern.firstMatch(fileName)?.group(1),
        title = title ?? _titlePart(fileName);

  static final _idPattern = RegExp(r'_(\d+)$');

  static String _titlePart(String fileName) {
    final withoutId = fileName.replaceFirst(_idPattern, '');
    // Creating a score replaces anything but letters, digits, "-" and "_"
    // in its title with "_", so "_" here most likely stood for a space.
    final spaced = withoutId.replaceAll('_', ' ').trim();
    return spaced.isEmpty ? fileName : spaced;
  }

  /// When the score was created, read from the [id].
  DateTime? get createdAt {
    final milliseconds = id == null ? null : int.tryParse(id!);
    return milliseconds == null ? null : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

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

  /// Every saved score with its title, in file-name order.
  Future<List<ScoreFileInfo>> listScores() async {
    final infos = <ScoreFileInfo>[];
    for (final fileName in await listScoreFileNames()) {
      String? title;
      try {
        title = (await load(fileName)).title;
      } catch (_) {
        // An unreadable file still gets listed, under its file name's title.
      }
      infos.add(ScoreFileInfo(fileName: fileName, title: title));
    }
    return infos;
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
