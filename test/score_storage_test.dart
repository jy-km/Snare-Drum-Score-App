import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/score_storage.dart';

void main() {
  test('A saved score\'s file name splits into its title and its ID', () {
    final info = ScoreFileInfo(fileName: 'Paradiddle_Warm_Up_1790812345678');

    expect(info.title, 'Paradiddle Warm Up');
    expect(info.id, '1790812345678');
    expect(info.createdAt, DateTime.fromMillisecondsSinceEpoch(1790812345678));
  });

  test('The title saved inside the file is preferred over the file name\'s', () {
    final info = ScoreFileInfo(fileName: 'Warm_Up_1790812345678', title: 'Warm-Up (slow)');

    expect(info.title, 'Warm-Up (slow)');
    expect(info.id, '1790812345678');
  });

  test('A title that itself ends in a number keeps it; only the last number is the ID', () {
    final info = ScoreFileInfo(fileName: 'Etude_12_1790812345678');

    expect(info.title, 'Etude 12');
    expect(info.id, '1790812345678');
  });

  test('A file not named by the app has no ID and is listed under its own name', () {
    final info = ScoreFileInfo(fileName: 'imported');

    expect(info.title, 'imported');
    expect(info.id, isNull);
    expect(info.createdAt, isNull);
  });

  test('A title made only of replaced characters falls back to the file name', () {
    final info = ScoreFileInfo(fileName: '__1790812345678');

    expect(info.title, '__1790812345678');
    expect(info.id, '1790812345678');
  });
}
