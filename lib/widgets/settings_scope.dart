import 'package:flutter/widgets.dart';

import '../services/app_settings.dart';

/// Makes the app's [AppSettings] available to every screen below it, and
/// rebuilds the screens that read them when a setting changes.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);

  /// Defaults, for a screen shown without a [SettingsScope] above it (as in
  /// most tests).
  static final _defaults = AppSettings();

  /// The settings in effect, and a dependency on them: the caller rebuilds
  /// when they change.
  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier ?? _defaults;
}
