import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/screens/review_screen.dart';
import 'package:snare_drum_score_app/widgets/offset_chart.dart';

import 'support/review_fixture.dart';

void main() {
  test('Early hits go above the middle and late ones below; the Good window fills it', () {
    expect(OffsetChart.yFraction(0), 0.5);
    expect(OffsetChart.yFraction(-0.06), lessThan(0.5), reason: 'early is up');
    expect(OffsetChart.yFraction(0.06), greaterThan(0.5), reason: 'late is down');
    expect(OffsetChart.yFraction(-0.12), closeTo(0, 1e-9));
    expect(OffsetChart.yFraction(0.12), closeTo(1, 1e-9));
    expect(OffsetChart.yFraction(0.5), 1, reason: 'kept inside the plot');
  });

  group('On the review screen', () {
    // sampleReview: four quarter notes at 4-7s, the measure 4-8s -- played
    // Perfect (+10ms), Great (+60ms), Good (-100ms), and the last missed.
    Future<void> pumpReview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ReviewScreen(review: sampleReview())));
    }

    /// Taps the chart where the note [fraction] of the way through the
    /// measure is plotted.
    Future<void> tapNoteAt(WidgetTester tester, double fraction) async {
      final plot = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('review_offset_chart')),
          matching: find.byType(CustomPaint),
        ),
      );
      // The chart's margin (40) and its inset at each end (10), and 10 on the right.
      final x = plot.left + 50 + fraction * (plot.width - 70);
      await tester.tapAt(Offset(x, plot.top + 40));
      await tester.pump();
    }

    String caption(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('offset_chart_caption'))).data!;

    testWidgets('is shown, and says what to do with it', (tester) async {
      await pumpReview(tester);
      expect(find.byKey(const Key('review_offset_chart')), findsOneWidget);
      expect(caption(tester), 'Tap a dot to see which note it was.');
    });

    testWidgets('tapping a dot says which note it was and how far off', (tester) async {
      await pumpReview(tester);

      await tapNoteAt(tester, 0.25);
      expect(caption(tester), 'Measure 1, note 2: Great+, +60 ms (late)');

      await tapNoteAt(tester, 0.5);
      expect(caption(tester), 'Measure 1, note 3: Good-, -100 ms (early)');
    });

    testWidgets('a missed note is there too, as not played', (tester) async {
      await pumpReview(tester);

      await tapNoteAt(tester, 0.75);

      expect(caption(tester), 'Measure 1, note 4: not played');
    });

    testWidgets('a tap far from every note picks nothing', (tester) async {
      await pumpReview(tester);

      await tapNoteAt(tester, 0.95);

      expect(caption(tester), 'Tap a dot to see which note it was.');
    });
  });
}
