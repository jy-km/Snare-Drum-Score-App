import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../services/practice_schedule.dart';
import 'accuracy_chart.dart' show shortDate;

/// What the player picked in [showSchedulePracticeDialog].
class ScheduleChoice {
  final PracticeRepeat repeat;
  final TimeOfDay time;

  /// For a weekly schedule: [DateTime.weekday] values, ascending.
  final List<int> weekdays;

  /// For a one-time session: the day.
  final DateTime date;

  const ScheduleChoice({
    required this.repeat,
    required this.time,
    required this.weekdays,
    required this.date,
  });
}

/// Asks how practice of [trackTitle] should be scheduled: every day, on
/// chosen days each week, or just once -- and at what time. Starts from
/// [current] when rescheduling. Returns null if cancelled.
Future<ScheduleChoice?> showSchedulePracticeDialog(
  BuildContext context, {
  required String trackTitle,
  ScheduledPractice? current,
}) {
  return showDialog<ScheduleChoice>(
    context: context,
    builder: (context) => _SchedulePracticeDialog(trackTitle: trackTitle, current: current),
  );
}

class _SchedulePracticeDialog extends StatefulWidget {
  final String trackTitle;
  final ScheduledPractice? current;

  const _SchedulePracticeDialog({required this.trackTitle, required this.current});

  @override
  State<_SchedulePracticeDialog> createState() => _SchedulePracticeDialogState();
}

class _SchedulePracticeDialogState extends State<_SchedulePracticeDialog> {
  late PracticeRepeat _repeat;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  late DateTime _date;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final now = clock.now();
    final current = widget.current;
    if (current != null) {
      _repeat = current.repeat;
      _time = TimeOfDay(hour: current.hour, minute: current.minute);
      _weekdays = current.weekdays.isEmpty ? {now.weekday} : {...current.weekdays};
      _date = current.onceAt ?? now;
    } else {
      // A fresh schedule repeats daily, at the next full hour.
      final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
      _repeat = PracticeRepeat.daily;
      _time = TimeOfDay(hour: nextHour.hour, minute: 0);
      _weekdays = {now.weekday};
      _date = nextHour;
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time, helpText: 'Practice at');
    if (time != null) setState(() => _time = time);
  }

  Future<void> _pickDate() async {
    final now = clock.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Practice on',
    );
    if (date != null) setState(() => _date = date);
  }

  bool get _canSchedule => _repeat != PracticeRepeat.weekly || _weekdays.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      key: const Key('schedule_dialog'),
      title: Text('Schedule practice: ${widget.trackTitle}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repeat', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<PracticeRepeat>(
              key: const Key('schedule_repeat'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PracticeRepeat.daily, label: Text('Every day')),
                ButtonSegment(value: PracticeRepeat.weekly, label: Text('Weekly')),
                ButtonSegment(value: PracticeRepeat.once, label: Text('Once')),
              ],
              selected: {_repeat},
              onSelectionChanged: (selection) => setState(() => _repeat = selection.single),
            ),
            if (_repeat == PracticeRepeat.weekly) ...[
              const SizedBox(height: 12),
              Text('On', style: textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      key: Key('schedule_day_$day'),
                      label: Text(_dayNames[day - 1]),
                      selected: _weekdays.contains(day),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _weekdays.add(day);
                        } else {
                          _weekdays.remove(day);
                        }
                      }),
                    ),
                ],
              ),
              if (_weekdays.isEmpty)
                Text(
                  'Pick at least one day.',
                  style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
            ],
            if (_repeat == PracticeRepeat.once)
              ListTile(
                key: const Key('schedule_date'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Date'),
                trailing: Text(shortDate(_date)),
                onTap: _pickDate,
              ),
            ListTile(
              key: const Key('schedule_time'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Time'),
              trailing: Text(localizations.formatTimeOfDay(_time, alwaysUse24HourFormat: true)),
              onTap: _pickTime,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('schedule_confirm'),
          onPressed: _canSchedule
              ? () => Navigator.of(context).pop(
                    ScheduleChoice(
                      repeat: _repeat,
                      time: _time,
                      weekdays: [..._weekdays]..sort(),
                      date: _date,
                    ),
                  )
              : null,
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}

/// How a schedule reads: "Every day, 18:00", "Weekdays, 07:30",
/// "Every Mon, Wed, Fri, 18:00", or for a one-time session "Tomorrow, 18:00".
String describeSchedule(ScheduledPractice practice) {
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(practice.hour)}:${two(practice.minute)}';
  switch (practice.repeat) {
    case PracticeRepeat.once:
      return describeWhen(practice.onceAt!);
    case PracticeRepeat.daily:
      return 'Every day, $time';
    case PracticeRepeat.weekly:
      final days = practice.weekdays;
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final String daysText;
      if (days.length == 7) {
        daysText = 'Every day';
      } else if (days.length == 5 && days.every((day) => day <= 5)) {
        daysText = 'Weekdays';
      } else if (days.length == 2 && days.every((day) => day >= 6)) {
        daysText = 'Weekends';
      } else {
        daysText = 'Every ${days.map((day) => names[day - 1]).join(', ')}';
      }
      return '$daysText, $time';
  }
}

/// "Today, 18:00", "Tomorrow, 07:30", or "Oct 9, 18:00".
String describeWhen(DateTime when) {
  final local = when.toLocal();
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final dayText = switch (day.difference(today).inDays) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => shortDate(local),
  };
  return '$dayText, $time';
}
