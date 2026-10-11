import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/history_screen.dart';
import 'package:snare_drum_score_app/screens/practice_screen.dart';
import 'package:snare_drum_score_app/screens/score_editor_screen.dart';
import 'package:snare_drum_score_app/screens/score_list_screen.dart';
import 'package:snare_drum_score_app/services/practice_history.dart';
import 'package:snare_drum_score_app/services/timeline_layout.dart';
import 'package:snare_drum_score_app/services/track_sections.dart';

import 'score_list_screen_test.dart' show InMemoryScoreStorage;
import 'support/fake_history.dart';
import 'support/review_fixture.dart';

class InMemorySectionStore implements SectionStore {
  List<TrackSection> saved;

  InMemorySectionStore([this.saved = const []]);

  @override
  Future<List<TrackSection>> load() async => saved;

  @override
  Future<void> save(List<TrackSection> sections) async => saved = sections;
}

/// A track of [count] measures, measure i (0-based) holding i+1 quarter
/// notes (capped at 4) -- so each measure is recognisable.
RhythmScore numberedTrack(String title, int count) => RhythmScore(
      title: title,
      tempoBpm: 72,
      instrument: Instrument.kick,
      measures: [
        for (var i = 0; i < count; i++)
          Measure(List.filled(i % 4 + 1, const RhythmEvent(NoteValue.quarter, EventType.normal))),
      ],
    );

TrackSection section(int first, int last, {String name = 'Fill', String id = 's1'}) =>
    TrackSection(id: id, trackId: 'Groove_1', name: name, firstMeasure: first, lastMeasure: last);

void main() {
  group('A section', () {
    test('is labelled by its measures, numbered from 1', () {
      expect(section(4, 7).rangeLabel, 'm. 5–8');
      expect(section(2, 2).rangeLabel, 'm. 3');
    });

    test('takes its measures from the mother track, with its tempo and instrument', () {
      final mother = numberedTrack('Groove', 8);

      final practised = section(1, 2).extractFrom(mother)!;

      expect(practised.measures, mother.measures.sublist(1, 3));
      expect(practised.title, 'Groove · Fill');
      expect(practised.tempoBpm, 72);
      expect(practised.instrument, Instrument.kick);
    });

    test('follows the mother track: an edit to it shows up in the section', () {
      final mother = numberedTrack('Groove', 8);
      final edited = mother.copyWithMeasure(
        2,
        Measure(const [RhythmEvent(NoteValue.eighth, EventType.accent)]),
      );

      expect(section(1, 2).extractFrom(edited)!.measures[1], edited.measures[2]);
    });

    test('is unusable once the mother track no longer reaches its measures', () {
      expect(section(6, 9).extractFrom(numberedTrack('Groove', 8)), isNull);
    });

    test('moves with the mother track\'s measures when one is deleted', () {
      final fill = section(4, 7); // measures 5-8
      expect(fill.afterMeasureDeleted(9), same(fill), reason: 'after it: unaffected');
      final shifted = fill.afterMeasureDeleted(1)!; // before it: moves up
      expect((shifted.firstMeasure, shifted.lastMeasure), (3, 6));
      final shrunk = fill.afterMeasureDeleted(5)!; // inside it: one shorter
      expect((shrunk.firstMeasure, shrunk.lastMeasure), (4, 6));
      expect(section(4, 4).afterMeasureDeleted(4), isNull, reason: 'its only measure is gone');
    });
  });

  group('Section storage', () {
    test('Sections are kept per track, in track order, and follow deleted measures', () async {
      final sections = TrackSections(InMemorySectionStore());
      await sections.put(section(4, 7, id: 'b', name: 'Ending'));
      await sections.put(section(0, 1, id: 'a', name: 'Intro'));
      await sections.put(const TrackSection(
        id: 'c',
        trackId: 'Other_2',
        name: 'Other',
        firstMeasure: 0,
        lastMeasure: 0,
      ));

      expect((await sections.forTrack('Groove_1')).map((s) => s.name), ['Intro', 'Ending']);

      await sections.measureDeleted('Groove_1', 2);
      final ending = (await sections.forTrack('Groove_1')).last;
      expect((ending.firstMeasure, ending.lastMeasure), (3, 6));
      expect((await sections.forTrack('Other_2')).single.firstMeasure, 0, reason: 'other tracks untouched');

      await sections.put(ending.copyWith(name: 'Outro'));
      expect((await sections.forTrack('Groove_1')).last.name, 'Outro');

      await sections.delete(ending);
      expect((await sections.forTrack('Groove_1')).map((s) => s.name), ['Intro']);

      await sections.deleteAllFor('Groove_1');
      expect(await sections.forTrack('Groove_1'), isEmpty);
      expect(await sections.forTrack('Other_2'), isNotEmpty);
    });

    test('The file store round-trips', () async {
      final root = await Directory.systemTemp.createTemp('sections_test');
      addTearDown(() => root.delete(recursive: true));
      final store = FileSectionStore(root: () async => root);

      await store.save([section(4, 7)]);
      final loaded = (await store.load()).single;

      expect((loaded.id, loaded.trackId, loaded.name, loaded.firstMeasure, loaded.lastMeasure),
          ('s1', 'Groove_1', 'Fill', 4, 7));
    });
  });

  test('A section\'s measures are numbered as in its track', () {
    final layout = TimelineLayout(numberedTrack('Groove', 2), firstMeasureNumber: 5);

    expect(layout.labelFor(0), 'Count-in');
    expect(layout.labelFor(1), 'Measure 5');
    expect(layout.labelFor(2), 'Measure 6');
    expect(layout.noteLocations.first, (5, 1));
    expect(layout.noteLocations.last, (6, 2));
  });

  group('On the main menu', () {
    late InMemoryScoreStorage storage;
    late InMemorySectionStore sectionStore;
    late InMemoryPracticeHistoryStore history;

    Future<void> pumpMenu(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ScoreListScreen(storage: storage, historyStore: history, sectionStore: sectionStore),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() async {
      storage = InMemoryScoreStorage();
      await storage.save('Groove_1', numberedTrack('Groove', 8));
      sectionStore = InMemorySectionStore();
      history = InMemoryPracticeHistoryStore();
    });

    Future<void> chooseMeasure(WidgetTester tester, String picker, int measure) async {
      await tester.tap(find.byKey(Key(picker)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measure $measure').last);
      await tester.pumpAndSettle();
    }

    testWidgets('The app is called MyTrak', (tester) async {
      await pumpMenu(tester);
      expect(find.text('MyTrak'), findsOneWidget);
    });

    testWidgets('New section... makes a named range, listed under its track', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.byKey(const Key('score_menu_Groove_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('score_menu_new_section')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('section_name')), 'Fill');
      await chooseMeasure(tester, 'section_from', 2);
      await chooseMeasure(tester, 'section_to', 3);
      await tester.tap(find.byKey(const Key('section_save')));
      await tester.pumpAndSettle();

      final saved = sectionStore.saved.single;
      expect((saved.trackId, saved.name, saved.firstMeasure, saved.lastMeasure),
          ('Groove_1', 'Fill', 1, 2));
      expect(find.textContaining('Fill'), findsOneWidget);
      expect(find.textContaining('m. 2–3'), findsOneWidget);
    });

    testWidgets('Practising a section plays just its measures, numbered as in the track',
        (tester) async {
      sectionStore.saved = [section(1, 2)];
      await pumpMenu(tester);

      await tester.tap(find.byKey(const Key('section_practice_s1')));
      await tester.pumpAndSettle();

      final practice = tester.widget<PracticeScreen>(find.byType(PracticeScreen));
      final mother = await storage.load('Groove_1');
      expect(practice.score.measures, mother.measures.sublist(1, 3));
      expect(practice.scoreId, 'Groove_1', reason: 'its runs go to the mother track');
      expect(practice.section!.id, 's1');
      expect(find.text('Practice: Groove · Fill'), findsOneWidget);
      expect(find.text('Measure 2'), findsOneWidget);
      expect(find.text('Measure 3'), findsOneWidget);
      expect(find.text('Measure 1'), findsNothing);
    });

    testWidgets('A section can be edited and deleted from its menu', (tester) async {
      sectionStore.saved = [section(1, 2)];
      await pumpMenu(tester);

      await tester.tap(find.byKey(const Key('section_menu_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('section_menu_edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('section_name')), 'Big fill');
      await chooseMeasure(tester, 'section_to', 5);
      await tester.tap(find.byKey(const Key('section_save')));
      await tester.pumpAndSettle();
      expect((sectionStore.saved.single.name, sectionStore.saved.single.lastMeasure),
          ('Big fill', 4));
      expect(find.textContaining('m. 2–5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('section_menu_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('section_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_section_confirm')));
      await tester.pumpAndSettle();

      expect(sectionStore.saved, isEmpty);
      expect(find.textContaining('Big fill'), findsNothing);
    });

    testWidgets('A section past the end of its track says so instead of practising',
        (tester) async {
      sectionStore.saved = [section(6, 9)];
      await pumpMenu(tester);

      await tester.tap(find.byKey(const Key('section_practice_s1')));
      await tester.pumpAndSettle();

      expect(find.byType(PracticeScreen), findsNothing);
      expect(find.textContaining('no longer has measures 7–10'), findsOneWidget);
    });

    testWidgets('Deleting a track deletes its sections', (tester) async {
      sectionStore.saved = [section(1, 2)];
      await pumpMenu(tester);

      await tester.tap(find.byKey(const Key('score_menu_Groove_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('score_menu_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(sectionStore.saved, isEmpty);
    });
  });

  group('In the editor', () {
    Future<InMemorySectionStore> pumpEditorAndDeleteMeasure2(
      WidgetTester tester, {
      required bool save,
    }) async {
      final sectionStore = InMemorySectionStore([section(4, 7)]);
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ScoreEditorScreen(
            fileName: 'Groove_1',
            initialScore: RhythmScore.empty(title: 'Groove'),
            sections: TrackSections(sectionStore),
            storage: InMemoryScoreStorage(),
          ),
        ),
      );
      final tab = find.byKey(const Key('measure_tab_1'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('measure_tab_delete')));
      await tester.pumpAndSettle();
      if (save) {
        final saveButton = find.byKey(const Key('save_button'));
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
      }
      return sectionStore;
    }

    testWidgets('Saving after deleting a measure moves the track\'s sections to follow',
        (tester) async {
      final sectionStore = await pumpEditorAndDeleteMeasure2(tester, save: true);

      final moved = sectionStore.saved.single;
      expect((moved.firstMeasure, moved.lastMeasure), (3, 6));
    });

    testWidgets('Leaving without saving leaves the sections as they were', (tester) async {
      final sectionStore = await pumpEditorAndDeleteMeasure2(tester, save: false);

      final kept = sectionStore.saved.single;
      expect((kept.firstMeasure, kept.lastMeasure), (4, 7));
    });
  });

  testWidgets('A section run is saved to the mother track\'s history, marked with the section',
      (tester) async {
    final history = InMemoryPracticeHistoryStore();
    await history.save(
      scoreId: 'Groove_1',
      review: sampleReview(),
      tempoBpm: 70,
      startedAt: DateTime(2026, 10, 7, 9, 0),
      section: const RunSection(name: 'Fill', firstMeasure: 4, lastMeasure: 7),
    );
    tester.view.physicalSize = const Size(412, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TrackHistoryScreen(scoreId: 'Groove_1', title: 'Groove', historyStore: history),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Section: Fill (m. 5–8)'), findsOneWidget);

    // Its review numbers the measures as in the track.
    final run = (await history.runsFor('Groove_1')).single;
    final review = await history.loadReview(run);
    expect(review.layout.labelFor(1), 'Measure 5');
    expect(review.locate(review.judgements[2]), 'Measure 5, note 3');
  });
}
