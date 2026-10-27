import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/widgets/confetti.dart';

void main() {
  Widget over(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Stack(
          children: [
            child,
            const Positioned.fill(child: ConfettiBurst()),
          ],
        ),
      ),
    ),
  );

  testWidgets('Taps go through it to what is underneath', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      over(
        Center(
          child: TextButton(onPressed: () => tapped = true, child: const Text('Under')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Under'));
    expect(tapped, isTrue);
    await tester.pumpAndSettle(); // it falls once, then stops
  });

  testWidgets('Not shown when the phone asks for less motion', (tester) async {
    await tester.pumpWidget(over(const SizedBox(), reduceMotion: true));
    expect(
      find.descendant(of: find.byType(ConfettiBurst), matching: find.byType(CustomPaint)),
      findsNothing,
    );
  });
}
