import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/screens/score_list_screen.dart';
import 'package:snare_drum_score_app/widgets/app_theme.dart';
import 'package:snare_drum_score_app/widgets/swipe_back.dart';

import 'score_list_screen_test.dart' show InMemoryScoreStorage;
import 'support/fake_history.dart';

/// A screen with a title, a button to open the next one, and a sideways
/// strip of chips like the editor's.
class _Screen extends StatelessWidget {
  final String title;
  final Widget? next;

  const _Screen(this.title, {this.next});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (next != null)
            TextButton(
              key: Key('open_from_$title'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => next!)),
              child: const Text('Next'),
            ),
          SizedBox(
            height: 48,
            child: ListView(
              key: Key('strip_$title'),
              scrollDirection: Axis.horizontal,
              children: [for (var i = 0; i < 30; i++) Chip(label: Text('$i'))],
            ),
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}

void main() {
  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => SwipeBack(navigatorKey: navigatorKey, child: child!),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpThreeDeep(WidgetTester tester) async {
    await pumpApp(tester, const _Screen('Home', next: _Screen('Track', next: _Screen('Run'))));
    await tester.tap(find.byKey(const Key('open_from_Home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_from_Track')));
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsOneWidget);
  }

  /// A quick swipe across the empty middle of the screen.
  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.flingFrom(const Offset(200, 400), Offset(dx, 0), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('Swiping right goes back a screen at a time, and stops at the main menu', (
    tester,
  ) async {
    await pumpThreeDeep(tester);

    await swipe(tester, 200);
    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Run'), findsNothing);

    await swipe(tester, 200);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Track'), findsNothing);

    await swipe(tester, 200);
    expect(find.text('Home'), findsOneWidget, reason: 'nowhere further back to go');
  });

  testWidgets('Swiping left, or a short nudge right, stays put', (tester) async {
    await pumpThreeDeep(tester);

    await swipe(tester, -200);
    expect(find.text('Run'), findsOneWidget);

    await tester.dragFrom(const Offset(200, 400), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('A slow drag right counts once it has crossed a third of the screen', (tester) async {
    await pumpThreeDeep(tester);

    final gesture = await tester.startGesture(const Offset(100, 400));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(15, 0), timeStamp: Duration(milliseconds: 100 * i));
    }
    await gesture.up(timeStamp: const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Track'), findsOneWidget);
  });

  testWidgets('A sideways strip keeps its own swipes', (tester) async {
    await pumpThreeDeep(tester);

    await tester.fling(find.byKey(const Key('strip_Run')), const Offset(200, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('An open dialog is closed by a swipe, leaving the screen under it', (tester) async {
    await pumpThreeDeep(tester);
    showDialog<void>(
      context: tester.element(find.text('Run')),
      builder: (_) => const AlertDialog(title: Text('Sure?')),
    );
    await tester.pumpAndSettle();

    await swipe(tester, 200);

    expect(find.text('Sure?'), findsNothing);
    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('From Settings, a swipe goes back to the main menu', (tester) async {
    await pumpApp(
      tester,
      ScoreListScreen(
        storage: InMemoryScoreStorage(),
        historyStore: InMemoryPracticeHistoryStore(),
      ),
    );
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await swipe(tester, 250);

    expect(find.text('Settings'), findsNothing);
    expect(find.text('MyTrak'), findsOneWidget);
  });
}
