import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/score_list_screen.dart';
import 'package:snare_drum_score_app/services/midi_score_codec.dart';
import 'package:snare_drum_score_app/services/score_storage.dart';

import 'support/fake_history.dart';

/// Keeps scores in memory, as the MIDI bytes the real storage would write.
class InMemoryScoreStorage extends ScoreStorage {
  final files = <String, List<int>>{};

  @override
  Future<List<String>> listScoreFileNames() async => files.keys.toList()..sort();

  @override
  Future<void> save(String fileName, RhythmScore score) async =>
      files[fileName] = MidiScoreCodec.encode(score);

  @override
  Future<RhythmScore> load(String fileName) async => MidiScoreCodec.decode(files[fileName]!);

  @override
  Future<void> delete(String fileName) async => files.remove(fileName);
}

void main() {
  const grooveFile = 'Groove_1790812345678';
  const fillFile = 'Fill_1790812349999';

  Future<InMemoryScoreStorage> pumpList(WidgetTester tester) async {
    final storage = InMemoryScoreStorage();
    await storage.save(grooveFile, RhythmScore.empty(title: 'Groove'));
    await storage.save(fillFile, RhythmScore.empty(title: 'Fill'));
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreListScreen(storage: storage, historyStore: InMemoryPracticeHistoryStore()),
      ),
    );
    await tester.pumpAndSettle();
    return storage;
  }

  Future<void> openMenu(WidgetTester tester, String fileName, String item) async {
    await tester.tap(find.byKey(Key('score_menu_$fileName')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(item)));
    await tester.pumpAndSettle();
  }

  testWidgets('Rename changes the title shown, keeping the file and its ID', (tester) async {
    final storage = await pumpList(tester);

    await openMenu(tester, grooveFile, 'score_menu_rename');
    await tester.enterText(find.byKey(const Key('title_field')), 'Slow Groove');
    await tester.tap(find.byKey(const Key('title_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Slow Groove'), findsOneWidget);
    expect(find.text('Groove'), findsNothing);
    expect(storage.files.keys, contains(grooveFile));
    expect((await storage.load(grooveFile)).title, 'Slow Groove');
  });

  testWidgets('Delete asks first, and removes the score only when confirmed', (tester) async {
    final storage = await pumpList(tester);

    await openMenu(tester, fillFile, 'score_menu_delete');
    expect(find.text('Delete "Fill"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.files.keys, contains(fillFile));
    expect(find.text('Fill'), findsOneWidget);

    await openMenu(tester, fillFile, 'score_menu_delete');
    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();

    expect(storage.files.keys, isNot(contains(fillFile)));
    expect(find.text('Fill'), findsNothing);
    expect(find.text('Groove'), findsOneWidget);
  });
}
