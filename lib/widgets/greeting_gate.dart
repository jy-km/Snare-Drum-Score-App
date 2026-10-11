import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../services/greetings.dart';
import 'schedule_practice_dialog.dart' show describeSchedule;
import 'schedule_scope.dart';
import 'settings_scope.dart';

/// Greets the player with a pop-up whenever the app is opened -- at launch,
/// and when coming back to it after a while away -- with their upcoming
/// scheduled practice listed underneath. Can be turned off in Settings.
class GreetingGate extends StatefulWidget {
  final Widget child;

  /// Where greetings are picked from; replaceable so tests get a known one.
  final Random? random;

  const GreetingGate({super.key, required this.child, this.random});

  /// Back after at least this long away counts as opening the app again;
  /// a quick switch to another app and back doesn't.
  static const awayLongEnough = Duration(minutes: 30);

  @override
  State<GreetingGate> createState() => _GreetingGateState();
}

class _GreetingGateState extends State<GreetingGate> with WidgetsBindingObserver {
  late final Random _random = widget.random ?? Random();
  DateTime? _leftAt;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = clock.now();
    } else if (state == AppLifecycleState.resumed) {
      final leftAt = _leftAt;
      _leftAt = null;
      if (leftAt != null && clock.now().difference(leftAt) >= GreetingGate.awayLongEnough) {
        _greet();
      }
    }
  }

  Future<void> _greet() async {
    if (!mounted || _showing || !SettingsScope.of(context).showGreeting) return;
    _showing = true;
    await showDialog<void>(
      context: context,
      builder: (context) => GreetingDialog(greeting: pickGreeting(clock.now(), _random)),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The greeting pop-up: a greeting, and the practice scheduled next.
class GreetingDialog extends StatelessWidget {
  final String greeting;

  const GreetingDialog({super.key, required this.greeting});

  /// How many upcoming sessions to list before summing up the rest.
  static const _listed = 3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final upcoming = ScheduleScope.of(context).upcoming;
    return AlertDialog(
      key: const Key('greeting_dialog'),
      titlePadding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(greeting, key: const Key('greeting_text')),
            ),
          ),
          IconButton(
            key: const Key('greeting_close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text('Scheduled practice', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          if (upcoming.isEmpty)
            Text(
              'Nothing scheduled. On the main menu, tap ⋮ on a track to schedule practice.',
              key: const Key('greeting_no_schedule'),
              style: textTheme.bodySmall,
            )
          else ...[
            for (final practice in upcoming.take(_listed))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.alarm, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${practice.trackTitle} · ${describeSchedule(practice)}',
                        key: Key('greeting_schedule_${practice.id}'),
                      ),
                    ),
                  ],
                ),
              ),
            if (upcoming.length > _listed)
              Text('and ${upcoming.length - _listed} more', style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
