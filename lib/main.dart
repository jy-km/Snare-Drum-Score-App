import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/score_list_screen.dart';
import 'services/click_sound.dart';

void main() {
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
  runApp(const SnareDrumScoreApp());
}

class SnareDrumScoreApp extends StatelessWidget {
  const SnareDrumScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyTempo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ScoreListScreen(),
    );
  }
}
