import 'package:flutter/material.dart';

import '../services/hit_judge.dart';
import '../widgets/judgement_style.dart';
import '../widgets/settings_scope.dart';

/// App-wide preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            key: const Key('setting_color_notes'),
            title: const Text('Colour notes by judgement'),
            subtitle: const Text(
              'In practice and review, each note turns the colour of how you played it. '
              'A rest you played in turns the Fail colour.',
            ),
            value: settings.colorNotesByJudgement,
            onChanged: (value) => settings.colorNotesByJudgement = value,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _JudgementColorKey(),
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('setting_greeting'),
            title: const Text('Greeting when the app opens'),
            subtitle: const Text('A hello, and a reminder of the practice you have scheduled.'),
            value: settings.showGreeting,
            onChanged: (value) => settings.showGreeting = value,
          ),
        ],
      ),
    );
  }
}

/// Which colour means which judgement.
class _JudgementColorKey extends StatelessWidget {
  const _JudgementColorKey();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final judgement in Judgement.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 12, color: judgementColor(judgement)),
              const SizedBox(width: 6),
              Text(judgementLabel(judgement)),
            ],
          ),
      ],
    );
  }
}
