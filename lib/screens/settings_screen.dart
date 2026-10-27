import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/hit_judge.dart';
import '../widgets/app_theme.dart';
import '../widgets/judgement_style.dart';
import '../widgets/settings_scope.dart';
import 'calibration_screen.dart';
import 'mic_test_screen.dart';

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
          ListTile(
            title: const Text('Appearance'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<Appearance>(
                key: const Key('setting_appearance'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: Appearance.system,
                    label: Text('Phone', key: Key('appearance_system')),
                  ),
                  ButtonSegment(
                    value: Appearance.light,
                    label: Text('Light', key: Key('appearance_light')),
                  ),
                  ButtonSegment(
                    value: Appearance.dark,
                    label: Text('Dark', key: Key('appearance_dark')),
                  ),
                ],
                selected: {settings.appearance},
                onSelectionChanged: (choice) => settings.appearance = choice.single,
              ),
            ),
          ),
          const Divider(),
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
            key: const Key('setting_confetti'),
            title: const Text('Confetti for great runs'),
            subtitle: const Text(
              'When a practice run ends above 90% accuracy -- and more of it for a run '
              "that's all Perfect.",
            ),
            value: settings.confetti,
            onChanged: (value) => settings.confetti = value,
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('setting_greeting'),
            title: const Text('Greeting when the app opens'),
            subtitle: const Text('A hello, and a reminder of the practice you have scheduled.'),
            value: settings.showGreeting,
            onChanged: (value) => settings.showGreeting = value,
          ),
          const Divider(),
          ListTile(
            key: const Key('calibration_button'),
            leading: const Icon(Icons.tune),
            title: const Text('Calibration'),
            subtitle: const Text("Play along to a beat so the app can measure your phone's delay."),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CalibrationScreen()),
            ),
          ),
          ListTile(
            key: const Key('mic_test_button'),
            leading: const Icon(Icons.mic_none),
            title: const Text('Mic test'),
            subtitle: const Text('Record a few hits and see which ones the app hears.'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MicTestScreen()),
            ),
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
              Icon(
                Icons.circle,
                size: 12,
                color: judgementColor(judgement, AppPalette.of(context)),
              ),
              const SizedBox(width: 6),
              Text(judgementLabel(judgement)),
            ],
          ),
      ],
    );
  }
}
