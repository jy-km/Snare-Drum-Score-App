import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/score_list_screen.dart';
import 'services/app_settings.dart';
import 'services/click_sound.dart';
import 'services/local_reminders.dart';
import 'services/practice_schedule.dart';
import 'widgets/greeting_gate.dart';
import 'widgets/schedule_scope.dart';
import 'widgets/settings_scope.dart';

Future<void> main() async {
  // rootBundle.load (used by ClickSound.preload below) needs the widgets
  // binding set up first -- runApp() does this too, but only once it starts,
  // which is after the fire-and-forget preload call below would already have
  // run and failed.
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: warms the hit-sound cache so the first Play/Practice
  // press doesn't pay the asset-load+decode latency. Errors are only
  // logged here -- ClickSound itself evicts a failed load from its cache, so
  // a real Play/Practice attempt later still gets to retry.
  unawaited(ClickSound.preload().catchError((Object error) {
    debugPrint('ClickSound.preload failed: $error');
  }));
  // Both read small local files, and the greeting shown at launch depends
  // on them (whether to show it, and what's scheduled), so they're read
  // before the first frame rather than after.
  final settings = AppSettings(store: const FileSettingsStore());
  final reminders = LocalReminderNotifier();
  unawaited(reminders.initialize().catchError((Object error) {
    debugPrint('Reminders failed to initialize: $error');
  }));
  final schedule = PracticeSchedule(store: const FileScheduleStore(), notifier: reminders);
  await Future.wait([settings.load(), schedule.load()]);
  runApp(SnareDrumScoreApp(settings: settings, schedule: schedule));
}

class SnareDrumScoreApp extends StatelessWidget {
  final AppSettings settings;
  final PracticeSchedule schedule;

  const SnareDrumScoreApp({super.key, required this.settings, required this.schedule});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyTrak',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // Above the navigator, so every screen pushed later sees the settings.
      builder: (context, child) => SettingsScope(
        settings: settings,
        child: ScheduleScope(schedule: schedule, child: child!),
      ),
      home: const GreetingGate(child: ScoreListScreen()),
    );
  }
}
