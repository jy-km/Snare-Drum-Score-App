import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/screens/score_list_screen.dart';
import 'package:snare_drum_score_app/screens/settings_screen.dart';
import 'package:snare_drum_score_app/services/app_settings.dart';
import 'package:snare_drum_score_app/services/hit_judge.dart';
import 'package:snare_drum_score_app/widgets/app_theme.dart';
import 'package:snare_drum_score_app/widgets/judgement_style.dart';
import 'package:snare_drum_score_app/widgets/settings_scope.dart';
import 'package:snare_drum_score_app/widgets/staff_notation_view.dart';

import 'note_colors_test.dart' show InMemorySettingsStore;
import 'score_list_screen_test.dart' show InMemoryScoreStorage;
import 'support/fake_history.dart';
import 'support/review_fixture.dart';

/// WCAG contrast ratio between two colours (1 to 21).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Palette', () {
    for (final (name, palette) in [('light', AppPalette.light), ('dark', AppPalette.dark)]) {
      test('Every judgement colour reads on the $name page, and no two are alike', () {
        final colors = [for (final j in Judgement.values) judgementColor(j, palette)];
        for (final (index, color) in colors.indexed) {
          final judgement = Judgement.values[index];
          // Yellow can't reach 3:1 on a light page and still look yellow;
          // the user's chosen Perfect (7.1) sits just under 2:1 there.
          final least = judgement == Judgement.perfect && palette == AppPalette.light ? 1.9 : 3.0;
          expect(
            contrast(color, palette.paper),
            greaterThanOrEqualTo(least),
            reason: '${judgement.name} on the $name page',
          );
        }
        expect(colors.toSet(), hasLength(Judgement.values.length));
        expect(contrast(palette.ink, palette.paper), greaterThanOrEqualTo(12), reason: 'ink');
      });
    }

    test('The theme carries its palette, and dark mode is dark', () {
      expect(buildAppTheme(Brightness.light).extension<AppPalette>(), AppPalette.light);
      final dark = buildAppTheme(Brightness.dark);
      expect(dark.extension<AppPalette>(), AppPalette.dark);
      expect(dark.scaffoldBackgroundColor.computeLuminance(), lessThan(0.05));
    });

    testWidgets('Without the app theme, screens get the light palette', (tester) async {
      late AppPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = AppPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(palette, AppPalette.light);
    });
  });

  group('Appearance setting', () {
    testWidgets('Follows the phone by default; choosing Dark is remembered', (tester) async {
      final store = InMemorySettingsStore();
      final settings = AppSettings(store: store);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SettingsScope(settings: settings, child: child!),
          home: const SettingsScreen(),
        ),
      );
      expect(settings.appearance, Appearance.system);

      await tester.tap(find.byKey(const Key('appearance_dark')));
      await tester.pump();

      expect(settings.appearance, Appearance.dark);
      expect(store.values['appearance'], 'dark');
    });

    test('A saved choice is loaded back; an unknown one falls back to the phone', () async {
      final settings = AppSettings(store: InMemorySettingsStore({'appearance': 'light'}));
      await settings.load();
      expect(settings.appearance, Appearance.light);

      final odd = AppSettings(store: InMemorySettingsStore({'appearance': 'sepia'}));
      await odd.load();
      expect(odd.appearance, Appearance.system);
    });
  });

  testWidgets('In dark mode, the review colours notes in the dark palette', (tester) async {
    final settings = AppSettings()..colorNotesByJudgement = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        builder: (context, child) => SettingsScope(settings: settings, child: child!),
        home: ReviewScreen(review: sampleReview()),
      ),
    );

    final colors = tester
        .widget<StaffNotationView>(find.byKey(const Key('review_measure_1')))
        .eventColors;
    expect(colors[0], AppPalette.dark.perfect);
  });

  testWidgets('Mic test and Calibration are in Settings, not on the home bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreListScreen(
          storage: InMemoryScoreStorage(),
          historyStore: InMemoryPracticeHistoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mic_test_button')), findsNothing);
    expect(find.byKey(const Key('calibration_button')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mic_test_button')), findsOneWidget);
    expect(find.byKey(const Key('calibration_button')), findsOneWidget);
  });
}
