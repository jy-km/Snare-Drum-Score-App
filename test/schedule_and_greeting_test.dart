import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/models/rhythm_score.dart';
import 'package:snare_drum_score_app/screens/history_screen.dart';
import 'package:snare_drum_score_app/screens/score_list_screen.dart';
import 'package:snare_drum_score_app/services/app_settings.dart';
import 'package:snare_drum_score_app/services/greetings.dart';
import 'package:snare_drum_score_app/services/practice_schedule.dart';
import 'package:snare_drum_score_app/widgets/greeting_gate.dart';
import 'package:snare_drum_score_app/widgets/schedule_practice_dialog.dart';
import 'package:snare_drum_score_app/widgets/schedule_scope.dart';
import 'package:snare_drum_score_app/widgets/settings_scope.dart';

import 'score_list_screen_test.dart' show InMemoryScoreStorage;
import 'support/fake_history.dart';
import 'support/review_fixture.dart';

/// Records what would have been put on the phone.
class FakeReminderNotifier implements ReminderNotifier {
  bool allowed = true;
  bool exact = true;
  final scheduled = <int, (ScheduledPractice, String)>{};
  int exactTimingRequests = 0;

  @override
  Future<bool> ensurePermission() async => allowed;

  @override
  Future<bool> schedule(ScheduledPractice practice, {required String body}) async {
    scheduled[practice.id] = (practice, body);
    return exact;
  }

  @override
  Future<void> cancel(ScheduledPractice practice) async => scheduled.remove(practice.id);

  @override
  Future<void> requestExactTiming() async => exactTimingRequests++;
}

class InMemoryScheduleStore implements ScheduleStore {
  List<ScheduledPractice> saved;

  InMemoryScheduleStore([this.saved = const []]);

  @override
  Future<List<ScheduledPractice>> load() async => saved;

  @override
  Future<void> save(List<ScheduledPractice> practices) async => saved = practices;
}

void main() {
  // Tests run on a fixed clock: Wednesday Oct 7 2026, 14:00.
  final now = DateTime(2026, 10, 7, 14, 0);

  ScheduledPractice practice({
    required PracticeRepeat repeat,
    int hour = 18,
    int minute = 0,
    List<int> weekdays = const [],
    DateTime? onceAt,
  }) =>
      ScheduledPractice(
        id: 1,
        scoreId: 'G',
        trackTitle: 'Groove',
        repeat: repeat,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        onceAt: onceAt,
      );

  group('When a session comes round', () {
    test('The test clock is a Wednesday', () => expect(now.weekday, DateTime.wednesday));

    test('Daily: today if the time is still ahead, else tomorrow', () {
      expect(practice(repeat: PracticeRepeat.daily, hour: 18).nextOccurrence(now),
          DateTime(2026, 10, 7, 18));
      expect(practice(repeat: PracticeRepeat.daily, hour: 9).nextOccurrence(now),
          DateTime(2026, 10, 8, 9));
    });

    test('Weekly: the soonest of the chosen days', () {
      // Mon and Fri, 18:00 -- from Wednesday afternoon, Friday comes first.
      final monFri = practice(repeat: PracticeRepeat.weekly, weekdays: [1, 5]);
      expect(monFri.nextOccurrence(now), DateTime(2026, 10, 9, 18));
      // Wednesday itself: later today, or (time passed) next Wednesday.
      expect(practice(repeat: PracticeRepeat.weekly, weekdays: [3]).nextOccurrence(now),
          DateTime(2026, 10, 7, 18));
      expect(practice(repeat: PracticeRepeat.weekly, weekdays: [3], hour: 9).nextOccurrence(now),
          DateTime(2026, 10, 14, 9));
    });

    test('Repeating sessions never run out; a one-time one does', () {
      expect(practice(repeat: PracticeRepeat.daily).isActive(now.add(const Duration(days: 999))),
          isTrue);
      final once = practice(repeat: PracticeRepeat.once, onceAt: DateTime(2026, 10, 8, 18));
      expect(once.isActive(now), isTrue);
      expect(once.isActive(DateTime(2026, 10, 9)), isFalse);
    });

    test('A weekly session sets one repeating notification per day, all distinct', () {
      final weekly = practice(repeat: PracticeRepeat.weekly, weekdays: [1, 3, 5]);
      expect(weekly.notificationIds.toSet().length, 3);
      expect(weekly.notificationIds.every((id) => id < (1 << 31)), isTrue);
      expect(practice(repeat: PracticeRepeat.daily).notificationIds, [1]);
    });

    test('Reads like a schedule', () {
      withClock(Clock.fixed(now), () {
        expect(describeSchedule(practice(repeat: PracticeRepeat.daily, hour: 7, minute: 30)),
            'Every day, 07:30');
        expect(describeSchedule(practice(repeat: PracticeRepeat.weekly, weekdays: [1, 3, 5])),
            'Every Mon, Wed, Fri, 18:00');
        expect(describeSchedule(practice(repeat: PracticeRepeat.weekly, weekdays: [1, 2, 3, 4, 5])),
            'Weekdays, 18:00');
        expect(describeSchedule(practice(repeat: PracticeRepeat.weekly, weekdays: [6, 7])),
            'Weekends, 18:00');
        expect(
          describeSchedule(practice(repeat: PracticeRepeat.once, onceAt: DateTime(2026, 10, 8, 18))),
          'Tomorrow, 18:00',
        );
      });
    });

    test('Sessions saved before repeating existed load as one-time sessions', () {
      final old = ScheduledPractice.fromJson({
        'id': 1790812345,
        'scoreId': 'G',
        'trackTitle': 'Groove',
        'runId': 'r1',
        'when': DateTime(2026, 10, 8, 18, 30).millisecondsSinceEpoch,
      });

      expect(old.repeat, PracticeRepeat.once);
      expect(old.onceAt, DateTime(2026, 10, 8, 18, 30));
      expect((old.hour, old.minute), (18, 30));
      expect(old.notificationIds, [1790812345], reason: 'so it can still be cancelled');
    });

    test('Round-trips through JSON', () {
      final weekly = practice(repeat: PracticeRepeat.weekly, weekdays: [2, 4], hour: 6, minute: 45);
      final back = ScheduledPractice.fromJson(weekly.toJson());

      expect(back.repeat, PracticeRepeat.weekly);
      expect(back.weekdays, [2, 4]);
      expect((back.hour, back.minute), (6, 45));
    });
  });

  group('Practice schedule', () {
    test('Adding a daily schedule sets a notification and keeps it', () async {
      await withClock(Clock.fixed(now), () async {
        final notifier = FakeReminderNotifier();
        final store = InMemoryScheduleStore();
        final schedule = PracticeSchedule(store: store, notifier: notifier);

        final outcome = await schedule.add(
          scoreId: 'Groove_1',
          trackTitle: 'Groove',
          repeat: PracticeRepeat.daily,
          hour: 18,
          minute: 0,
          body: 'Your practice session for Groove is now.',
        );

        expect(outcome, ScheduleOutcome.scheduled);
        final (set, body) = notifier.scheduled.values.single;
        expect(set.repeat, PracticeRepeat.daily);
        expect((set.hour, set.minute), (18, 0));
        expect(body, 'Your practice session for Groove is now.');
        expect(store.saved.single.scoreId, 'Groove_1');
      });
    });

    test('Nothing is set for a past one-time session, a weekly one with no days, or no permission',
        () async {
      await withClock(Clock.fixed(now), () async {
        final notifier = FakeReminderNotifier();
        final schedule = PracticeSchedule(notifier: notifier);
        Future<ScheduleOutcome> add(PracticeRepeat repeat) => schedule.add(
              scoreId: 'G',
              trackTitle: 'G',
              repeat: repeat,
              hour: 9, // already passed today
              minute: 0,
              onceOn: now,
              body: '',
            );

        expect(await add(PracticeRepeat.once), ScheduleOutcome.inThePast);
        expect(await add(PracticeRepeat.weekly), ScheduleOutcome.noDaysChosen);
        notifier.allowed = false;
        expect(await add(PracticeRepeat.daily), ScheduleOutcome.notificationsNotAllowed);
        expect(notifier.scheduled, isEmpty);
        expect(schedule.upcoming, isEmpty);
      });
    });

    test('A daily time already passed today is fine: it starts tomorrow', () async {
      await withClock(Clock.fixed(now), () async {
        final schedule = PracticeSchedule(notifier: FakeReminderNotifier());

        expect(
          await schedule.add(
            scoreId: 'G',
            trackTitle: 'G',
            repeat: PracticeRepeat.daily,
            hour: 9,
            minute: 0,
            body: '',
          ),
          ScheduleOutcome.scheduled,
        );
        expect(schedule.upcoming.single.nextOccurrence(now), DateTime(2026, 10, 8, 9));
      });
    });

    test('Without exact timing allowed, it says reminders may be late', () async {
      await withClock(Clock.fixed(now), () async {
        final schedule = PracticeSchedule(notifier: FakeReminderNotifier()..exact = false);

        expect(
          await schedule.add(
            scoreId: 'G',
            trackTitle: 'G',
            repeat: PracticeRepeat.daily,
            hour: 18,
            minute: 0,
            body: '',
          ),
          ScheduleOutcome.scheduledApproximately,
        );
      });
    });

    test('Scheduling a track again replaces its schedule; cancelling removes it', () async {
      await withClock(Clock.fixed(now), () async {
        final notifier = FakeReminderNotifier();
        final schedule = PracticeSchedule(notifier: notifier);
        await schedule.add(
          scoreId: 'G',
          trackTitle: 'G',
          repeat: PracticeRepeat.daily,
          hour: 9,
          minute: 0,
          body: '',
        );
        await schedule.add(
          scoreId: 'G',
          trackTitle: 'G',
          repeat: PracticeRepeat.weekly,
          weekdays: const [2, 4],
          hour: 18,
          minute: 0,
          body: '',
        );

        expect(schedule.upcoming.single.repeat, PracticeRepeat.weekly);
        expect(notifier.scheduled.length, 1);

        await schedule.cancel(schedule.upcoming.single);
        expect(schedule.upcoming, isEmpty);
        expect(notifier.scheduled, isEmpty);
      });
    });

    test('Loading keeps repeating sessions and drops past one-time ones, soonest first', () async {
      await withClock(Clock.fixed(now), () async {
        final store = InMemoryScheduleStore([
          ScheduledPractice(
            id: 1,
            scoreId: 'A',
            trackTitle: 'A',
            repeat: PracticeRepeat.once,
            hour: 8,
            minute: 0,
            onceAt: DateTime(2026, 10, 6, 8), // past
          ),
          const ScheduledPractice(
            id: 2,
            scoreId: 'B',
            trackTitle: 'B',
            repeat: PracticeRepeat.weekly,
            weekdays: [5],
            hour: 8,
            minute: 0,
          ),
          const ScheduledPractice(
            id: 3,
            scoreId: 'C',
            trackTitle: 'C',
            repeat: PracticeRepeat.daily,
            hour: 8,
            minute: 0,
          ),
        ]);
        final schedule = PracticeSchedule(store: store);

        await schedule.load();

        expect(schedule.upcoming.map((p) => p.id), [3, 2], reason: 'Thursday 8:00, then Friday');
        expect(store.saved.map((p) => p.id), unorderedEquals([2, 3]));
      });
    });
  });

  group('Scheduling from the main menu', () {
    Future<(FakeReminderNotifier, PracticeSchedule)> pumpMenu(WidgetTester tester) async {
      final storage = InMemoryScoreStorage();
      await storage.save('Groove_1', RhythmScore.empty(title: 'Groove'));
      final notifier = FakeReminderNotifier();
      final schedule = PracticeSchedule(notifier: notifier);
      tester.view.physicalSize = const Size(412, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ScheduleScope(schedule: schedule, child: child!),
          home: ScoreListScreen(storage: storage, historyStore: InMemoryPracticeHistoryStore()),
        ),
      );
      await tester.pumpAndSettle();
      return (notifier, schedule);
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('score_menu_Groove_1')));
      await tester.pumpAndSettle();
    }

    Future<void> openScheduleForm(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.byKey(const Key('score_menu_schedule')));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('schedule_confirm')));
      await tester.pumpAndSettle();
    }

    testWidgets('The ⋮ menu offers Schedule practice before Rename and Delete, then More info',
        (tester) async {
      await pumpMenu(tester);
      await openMenu(tester);

      final order = [
        for (final label in ['Schedule practice', 'Rename', 'Delete', 'More info...'])
          tester.getTopLeft(find.text(label)).dy,
      ];
      expect(order, orderedEquals([...order]..sort()));
    });

    testWidgets('A new schedule repeats every day by default, at the next full hour',
        (tester) async {
      await withClock(Clock.fixed(now), () async {
        final (notifier, _) = await pumpMenu(tester);
        await openScheduleForm(tester);

        expect(find.text('15:00'), findsOneWidget);
        await confirm(tester);

        final (set, body) = notifier.scheduled.values.single;
        expect(set.repeat, PracticeRepeat.daily);
        expect((set.hour, set.minute), (15, 0));
        expect(set.trackTitle, 'Groove');
        expect(body, 'Your practice session for Groove is now.');
        expect(find.text('Practice scheduled: Every day, 15:00'), findsNWidgets(2),
            reason: 'the confirmation, and the line on the track');
      });
    });

    testWidgets('Weekly: on the days ticked', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final (notifier, _) = await pumpMenu(tester);
        await openScheduleForm(tester);

        await tester.tap(find.text('Weekly'));
        await tester.pumpAndSettle();
        // Wednesday (today) starts ticked; add Monday and Friday.
        await tester.tap(find.byKey(const Key('schedule_day_1')));
        await tester.tap(find.byKey(const Key('schedule_day_5')));
        await tester.pumpAndSettle();
        await confirm(tester);

        final (set, _) = notifier.scheduled.values.single;
        expect(set.repeat, PracticeRepeat.weekly);
        expect(set.weekdays, [1, 3, 5]);
        expect(find.text('Practice scheduled: Every Mon, Wed, Fri, 15:00'), findsWidgets);
      });
    });

    testWidgets('Weekly with no days can\'t be scheduled', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await pumpMenu(tester);
        await openScheduleForm(tester);

        await tester.tap(find.text('Weekly'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('schedule_day_3'))); // untick Wednesday
        await tester.pumpAndSettle();

        expect(find.text('Pick at least one day.'), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byKey(const Key('schedule_confirm')));
        expect(button.onPressed, isNull);
      });
    });

    testWidgets('Once: a single session on a chosen date', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final (notifier, _) = await pumpMenu(tester);
        await openScheduleForm(tester);

        await tester.tap(find.text('Once'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('schedule_date')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('8'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await confirm(tester);

        final (set, _) = notifier.scheduled.values.single;
        expect(set.repeat, PracticeRepeat.once);
        expect(set.onceAt, DateTime(2026, 10, 8, 15, 0));
        expect(find.text('Practice scheduled: Tomorrow, 15:00'), findsWidgets);
      });
    });

    testWidgets('Rescheduling starts from the current schedule; the menu can cancel it',
        (tester) async {
      await withClock(Clock.fixed(now), () async {
        final (notifier, schedule) = await pumpMenu(tester);
        await openScheduleForm(tester);
        await tester.tap(find.text('Weekly'));
        await tester.pumpAndSettle();
        await confirm(tester);

        await openMenu(tester);
        await tester.tap(find.text('Reschedule practice'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilterChip>(find.byKey(const Key('schedule_day_3'))).selected,
          isTrue,
          reason: 'the form opens on the current weekly schedule',
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await openMenu(tester);
        await tester.tap(find.byKey(const Key('score_menu_unschedule')));
        await tester.pumpAndSettle();

        expect(notifier.scheduled, isEmpty);
        expect(schedule.upcoming, isEmpty);
        expect(find.byKey(const Key('score_scheduled_Groove_1')), findsNothing);
      });
    });

    testWidgets('More info... in the ⋮ menu shows the track\'s ID', (tester) async {
      await pumpMenu(tester);
      await openMenu(tester);

      await tester.tap(find.byKey(const Key('score_menu_more_info')));
      await tester.pumpAndSettle();

      expect(find.text('ID: 1'), findsOneWidget);
    });

    testWidgets('Recordings in History have no scheduling of their own', (tester) async {
      final history = InMemoryPracticeHistoryStore();
      final run = await history.save(
        scoreId: 'Groove_1',
        review: sampleReview(),
        tempoBpm: 70,
        startedAt: DateTime(2026, 10, 7, 9, 0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrackHistoryScreen(scoreId: 'Groove_1', title: 'Groove', historyStore: history),
        ),
      );
      await tester.pumpAndSettle();

      // Below the charts.
      await tester.scrollUntilVisible(find.byKey(Key('run_menu_${run.id}')), 200);
      await tester.tap(find.byKey(Key('run_menu_${run.id}')));
      await tester.pumpAndSettle();

      expect(find.textContaining('chedule'), findsNothing);
      expect(find.text('Add note'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('Greeting', () {
    test('Fits the time of day, or any time', () {
      final random = Random(1);
      final lateNight = {for (var i = 0; i < 200; i++) pickGreeting(DateTime(2026, 10, 7, 2), random)};
      final morning = {for (var i = 0; i < 200; i++) pickGreeting(DateTime(2026, 10, 7, 8), random)};

      expect(lateNight, contains('Greetings, night owl.'));
      expect(lateNight, contains('Practicing instead of scrolling?'));
      expect(lateNight.any((line) => line.contains('morning')), isFalse);
      expect(morning.any((line) => line.contains('night owl')), isFalse);
      expect(lateNight.length + morning.length, greaterThan(15), reason: 'plenty of variety');
    });

    Future<void> pumpApp(WidgetTester tester,
        {required AppSettings settings, required PracticeSchedule schedule}) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SettingsScope(
            settings: settings,
            child: ScheduleScope(schedule: schedule, child: child!),
          ),
          home: GreetingGate(random: Random(0), child: const Scaffold(body: Text('Main menu'))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Pops up when the app opens, listing scheduled practice, soonest first',
        (tester) async {
      await withClock(Clock.fixed(now), () async {
        final schedule = PracticeSchedule(notifier: FakeReminderNotifier());
        await schedule.add(
          scoreId: 'F',
          trackTitle: 'Fill',
          repeat: PracticeRepeat.weekly,
          weekdays: const [1, 5],
          hour: 7,
          minute: 0,
          body: '',
        );
        await schedule.add(
          scoreId: 'G',
          trackTitle: 'Groove',
          repeat: PracticeRepeat.daily,
          hour: 18,
          minute: 30,
          body: '',
        );

        await pumpApp(tester, settings: AppSettings(), schedule: schedule);

        expect(find.byKey(const Key('greeting_dialog')), findsOneWidget);
        final groove = find.text('Groove · Every day, 18:30');
        final fill = find.text('Fill · Every Mon, Fri, 07:00');
        expect(groove, findsOneWidget);
        expect(fill, findsOneWidget);
        expect(tester.getTopLeft(groove).dy, lessThan(tester.getTopLeft(fill).dy),
            reason: 'today 18:30 comes before Friday 07:00');
        expect(
          tester.getTopLeft(groove).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('greeting_text'))).dy),
          reason: 'the schedule is at the bottom, under the greeting',
        );
      });
    });

    testWidgets('Can be closed', (tester) async {
      await pumpApp(tester, settings: AppSettings(), schedule: PracticeSchedule());
      expect(find.byKey(const Key('greeting_no_schedule')), findsOneWidget);

      await tester.tap(find.byKey(const Key('greeting_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('greeting_dialog')), findsNothing);
      expect(find.text('Main menu'), findsOneWidget);
    });

    testWidgets('Doesn\'t pop up when turned off in Settings', (tester) async {
      await pumpApp(tester,
          settings: AppSettings()..showGreeting = false, schedule: PracticeSchedule());

      expect(find.byKey(const Key('greeting_dialog')), findsNothing);
    });

    testWidgets('Greets again on coming back after a while, not after a quick switch',
        (tester) async {
      var time = now;
      await withClock(Clock(() => time), () async {
        await pumpApp(tester, settings: AppSettings(), schedule: PracticeSchedule());
        await tester.tap(find.byKey(const Key('greeting_close')));
        await tester.pumpAndSettle();

        void lifecycle(AppLifecycleState state) =>
            tester.binding.handleAppLifecycleStateChanged(state);

        lifecycle(AppLifecycleState.paused);
        time = time.add(const Duration(minutes: 5));
        lifecycle(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('greeting_dialog')), findsNothing);

        lifecycle(AppLifecycleState.paused);
        time = time.add(const Duration(hours: 2));
        lifecycle(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('greeting_dialog')), findsOneWidget);
      });
    });
  });
}
