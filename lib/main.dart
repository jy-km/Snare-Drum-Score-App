import 'package:flutter/material.dart';

import 'screens/score_list_screen.dart';

void main() {
  runApp(const SnareDrumScoreApp());
}

class SnareDrumScoreApp extends StatelessWidget {
  const SnareDrumScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snare Drum Score',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ScoreListScreen(),
    );
  }
}
