import 'package:flutter/material.dart';

/// Swiping a finger to the right, anywhere on the screen, goes back one
/// screen -- as the phone's back button does -- and so on screen by screen
/// until the main menu, where it does nothing. An open dialog or menu is
/// closed the same way.
///
/// Anything that scrolls or drags sideways itself (the editor's measure
/// strip, the length buttons, a text field) keeps its own swipes: it sits
/// deeper than this and so gets them first.
class SwipeBack extends StatefulWidget {
  /// The navigator to go back in.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// How far the finger must travel to the right, and how fast it must be
  /// going when lifted -- a deliberate swipe, not a slip while tapping.
  static const double minDistance = 80;
  static const double minSpeed = 300;

  const SwipeBack({super.key, required this.navigatorKey, required this.child});

  @override
  State<SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<SwipeBack> {
  double _dx = 0;
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dx = _dy = 0,
      onHorizontalDragUpdate: (details) {
        _dx += details.delta.dx;
        _dy += details.delta.dy;
      },
      onHorizontalDragEnd: (details) {
        final rightward = _dx >= SwipeBack.minDistance && _dx > 2 * _dy.abs();
        final fastEnough = details.velocity.pixelsPerSecond.dx >= SwipeBack.minSpeed;
        // A slow drag counts too once it's crossed a third of the screen.
        final farEnough = _dx >= MediaQuery.sizeOf(context).width / 3;
        if (rightward && (fastEnough || farEnough)) {
          widget.navigatorKey.currentState?.maybePop();
        }
      },
      child: widget.child,
    );
  }
}
