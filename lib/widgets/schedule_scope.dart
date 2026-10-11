import 'package:flutter/widgets.dart';

import '../services/practice_schedule.dart';

/// Makes the player's [PracticeSchedule] available to every screen below
/// it, and rebuilds the screens that read it when it changes.
class ScheduleScope extends InheritedNotifier<PracticeSchedule> {
  const ScheduleScope({super.key, required PracticeSchedule schedule, required super.child})
      : super(notifier: schedule);

  /// For a screen shown without a [ScheduleScope] above it (as in most
  /// tests): an empty schedule that sets no real notifications.
  static final _fallback = PracticeSchedule();

  static PracticeSchedule of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleScope>()?.notifier ?? _fallback;
}
