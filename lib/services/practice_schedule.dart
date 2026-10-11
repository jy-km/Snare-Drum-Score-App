import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// How a scheduled practice session repeats.
enum PracticeRepeat {
  /// One time only, at [ScheduledPractice.onceAt].
  once,

  /// Every day at the set time.
  daily,

  /// Every week, on [ScheduledPractice.weekdays], at the set time.
  weekly,
}

/// A practice session the player scheduled for a track: at each occurrence,
/// a notification asks them to practise [trackTitle]. A daily or weekly
/// session keeps going until it's cancelled; a one-time one is over once
/// its moment has passed.
@immutable
class ScheduledPractice {
  /// Identifies the session; its notifications' ids are derived from it
  /// ([notificationIds]).
  final int id;
  final String scoreId;
  final String trackTitle;

  /// The recording it was scheduled from, if any. (Sessions are scheduled
  /// per track, from the main menu; kept for sessions saved back when they
  /// were scheduled from recordings.)
  final String? runId;

  final PracticeRepeat repeat;

  /// Time of day, for every repeat kind.
  final int hour;
  final int minute;

  /// For [PracticeRepeat.weekly]: which days, as [DateTime.weekday] values
  /// (1 = Monday ... 7 = Sunday), ascending.
  final List<int> weekdays;

  /// For [PracticeRepeat.once]: the date and time.
  final DateTime? onceAt;

  const ScheduledPractice({
    required this.id,
    required this.scoreId,
    required this.trackTitle,
    this.runId,
    required this.repeat,
    required this.hour,
    required this.minute,
    this.weekdays = const [],
    this.onceAt,
  });

  /// The id of each notification the session sets on the phone: one, or
  /// one per weekday for a weekly session (each repeating on its own day).
  /// Kept under 2^31, the largest id the phone accepts.
  List<int> get notificationIds => repeat == PracticeRepeat.weekly
      ? [for (final day in weekdays) (id % (1 << 27)) * 8 + day]
      : [id];

  /// When the session next comes round after [now] -- or, for a one-time
  /// session, its moment, even if passed.
  DateTime nextOccurrence(DateTime now) {
    switch (repeat) {
      case PracticeRepeat.once:
        return onceAt!;
      case PracticeRepeat.daily:
        final today = DateTime(now.year, now.month, now.day, hour, minute);
        return today.isAfter(now) ? today : _addDays(today, 1);
      case PracticeRepeat.weekly:
        return [for (final day in weekdays) nextOnWeekday(day, now)]
            .reduce((a, b) => a.isBefore(b) ? a : b);
    }
  }

  /// When this session's time of day next falls on [weekday] after [now].
  DateTime nextOnWeekday(int weekday, DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    var daysAhead = (weekday - now.weekday) % 7;
    if (daysAhead == 0 && !today.isAfter(now)) daysAhead = 7;
    return _addDays(today, daysAhead);
  }

  /// Calendar days, keeping the wall-clock time across daylight saving.
  static DateTime _addDays(DateTime time, int days) =>
      DateTime(time.year, time.month, time.day + days, time.hour, time.minute);

  /// Whether it will still come round: repeating sessions always do.
  bool isActive(DateTime now) => repeat != PracticeRepeat.once || onceAt!.isAfter(now);

  Map<String, Object?> toJson() => {
        'id': id,
        'scoreId': scoreId,
        'trackTitle': trackTitle,
        'runId': runId,
        'repeat': repeat.name,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        if (onceAt != null) 'when': onceAt!.millisecondsSinceEpoch,
      };

  static ScheduledPractice fromJson(Map<String, dynamic> json) {
    final whenMillis = json['when'] as int?;
    final onceAt = whenMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(whenMillis);
    return ScheduledPractice(
      id: json['id'] as int,
      scoreId: json['scoreId'] as String,
      trackTitle: json['trackTitle'] as String,
      runId: json['runId'] as String?,
      // Sessions saved before repeating existed were all one-time.
      repeat: PracticeRepeat.values.byName(json['repeat'] as String? ?? 'once'),
      hour: json['hour'] as int? ?? onceAt!.hour,
      minute: json['minute'] as int? ?? onceAt!.minute,
      weekdays: [for (final day in json['weekdays'] as List? ?? const []) day as int],
      onceAt: onceAt,
    );
  }
}

/// What came of asking for a reminder.
enum ScheduleOutcome {
  /// Set, and the phone will deliver it on the minute.
  scheduled,

  /// Set, but the phone only allows approximate timing for this app, so it
  /// may arrive a few minutes late (see [ReminderNotifier.requestExactTiming]).
  scheduledApproximately,

  /// A one-time session whose moment has already passed.
  inThePast,

  /// A weekly session with no days chosen.
  noDaysChosen,

  /// The player didn't allow notifications.
  notificationsNotAllowed,
}

/// Puts reminders on the phone. An interface so tests (and screens shown
/// without the real thing) don't touch the platform.
abstract class ReminderNotifier {
  /// Asks to be allowed to show notifications, if not asked before.
  Future<bool> ensurePermission();

  /// Sets [practice]'s notifications -- repeating ones repeat on the phone
  /// by themselves; returns whether they will be delivered on the minute.
  Future<bool> schedule(ScheduledPractice practice, {required String body});

  /// Removes all of [practice]'s notifications.
  Future<void> cancel(ScheduledPractice practice);

  /// Asks the player to allow on-the-minute reminders (Android's "alarms &
  /// reminders" permission).
  Future<void> requestExactTiming();
}

/// Does nothing -- for screens shown without a real notifier.
class NoReminderNotifier implements ReminderNotifier {
  const NoReminderNotifier();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<bool> schedule(ScheduledPractice practice, {required String body}) async => true;

  @override
  Future<void> cancel(ScheduledPractice practice) async {}

  @override
  Future<void> requestExactTiming() async {}
}

/// Keeps the list of scheduled practice between launches.
abstract class ScheduleStore {
  Future<List<ScheduledPractice>> load();
  Future<void> save(List<ScheduledPractice> practices);
}

class FileScheduleStore implements ScheduleStore {
  const FileScheduleStore();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/practice_schedule.json');
  }

  @override
  Future<List<ScheduledPractice>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    return [
      for (final entry in jsonDecode(await file.readAsString()) as List)
        ScheduledPractice.fromJson(entry as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> save(List<ScheduledPractice> practices) async {
    final file = await _file();
    await file.writeAsString(jsonEncode([for (final practice in practices) practice.toJson()]));
  }
}

/// The player's scheduled practice sessions, one per track at most. Screens
/// listen to it (through `ScheduleScope`).
class PracticeSchedule extends ChangeNotifier {
  final ScheduleStore? _store;
  final ReminderNotifier _notifier;

  /// Without a [store], the schedule lasts only as long as this object;
  /// without a [notifier], no notifications are actually set.
  PracticeSchedule({this._store, this._notifier = const NoReminderNotifier()});

  List<ScheduledPractice> _all = const [];

  /// Sessions still to come, the one coming round soonest first.
  List<ScheduledPractice> get upcoming {
    final now = clock.now();
    return _all.where((practice) => practice.isActive(now)).toList()
      ..sort((a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
  }

  /// The session scheduled for track [scoreId], if any.
  ScheduledPractice? forTrack(String scoreId) {
    for (final practice in upcoming) {
      if (practice.scoreId == scoreId) return practice;
    }
    return null;
  }

  /// Reads the saved schedule, dropping one-time sessions already past.
  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    try {
      _all = await store.load();
      final stillActive = upcoming;
      if (stillActive.length != _all.length) {
        _all = stillActive;
        await store.save(_all);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Could not load the practice schedule: $e');
    }
  }

  /// Schedules practice of a track -- replacing any session it already had.
  /// [onceOn] is the date for a one-time session; [weekdays] the days for a
  /// weekly one.
  Future<ScheduleOutcome> add({
    required String scoreId,
    required String trackTitle,
    required PracticeRepeat repeat,
    required int hour,
    required int minute,
    List<int> weekdays = const [],
    DateTime? onceOn,
    required String body,
  }) async {
    final now = clock.now();
    final onceAt = repeat == PracticeRepeat.once
        ? DateTime(onceOn!.year, onceOn.month, onceOn.day, hour, minute)
        : null;
    if (onceAt != null && !onceAt.isAfter(now)) return ScheduleOutcome.inThePast;
    if (repeat == PracticeRepeat.weekly && weekdays.isEmpty) return ScheduleOutcome.noDaysChosen;
    if (!await _notifier.ensurePermission()) return ScheduleOutcome.notificationsNotAllowed;

    // Seconds since 1970, wrapped to leave room for weekly sessions'
    // per-day notification ids, and bumped past any id already in use.
    var id = (now.millisecondsSinceEpoch ~/ 1000) % (1 << 27);
    while (_all.any((other) => other.id == id)) {
      id++;
    }
    final practice = ScheduledPractice(
      id: id,
      scoreId: scoreId,
      trackTitle: trackTitle,
      repeat: repeat,
      hour: hour,
      minute: minute,
      weekdays: repeat == PracticeRepeat.weekly ? ([...weekdays.toSet()]..sort()) : const [],
      onceAt: onceAt,
    );
    // One session per track: a new one replaces the old.
    final replaced = forTrack(scoreId);
    if (replaced != null) await cancel(replaced);

    final exact = await _notifier.schedule(practice, body: body);
    _all = [...upcoming, practice];
    notifyListeners();
    await _save();
    return exact ? ScheduleOutcome.scheduled : ScheduleOutcome.scheduledApproximately;
  }

  Future<void> cancel(ScheduledPractice practice) async {
    await _notifier.cancel(practice);
    _all = [for (final other in _all) if (other.id != practice.id) other];
    notifyListeners();
    await _save();
  }

  /// Cancels a track's session (e.g. when the track is deleted).
  Future<void> cancelAllFor(String scoreId) async {
    for (final practice in [..._all]) {
      if (practice.scoreId == scoreId) await cancel(practice);
    }
  }

  Future<void> requestExactTiming() => _notifier.requestExactTiming();

  Future<void> _save() async {
    try {
      await _store?.save(_all);
    } catch (e) {
      debugPrint('Could not save the practice schedule: $e');
    }
  }
}
