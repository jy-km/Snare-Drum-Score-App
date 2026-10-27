import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Light or dark pages, or whichever the phone is set to.
enum Appearance { system, light, dark }

/// The user's app-wide preferences, as set on the Settings screen. Screens
/// listen to it (through `SettingsScope`) and redraw when it changes.
class AppSettings extends ChangeNotifier {
  final SettingsStore? _store;

  /// Without a [store], settings last only as long as this object.
  AppSettings({this._store});

  /// In practice and review, draw each note in the colour of the judgement
  /// it got (Perfect, Great, Good, Miss), and a rest that was played in in
  /// the Fail colour. Off by default.
  bool get colorNotesByJudgement => _colorNotesByJudgement;
  bool _colorNotesByJudgement = false;

  set colorNotesByJudgement(bool value) {
    if (value == _colorNotesByJudgement) return;
    _colorNotesByJudgement = value;
    notifyListeners();
    _save();
  }

  /// Greet the player with a pop-up when the app opens (with their
  /// upcoming scheduled practice underneath). On by default.
  bool get showGreeting => _showGreeting;
  bool _showGreeting = true;

  set showGreeting(bool value) {
    if (value == _showGreeting) return;
    _showGreeting = value;
    notifyListeners();
    _save();
  }

  /// Confetti when a practice run ends above 90% accuracy (more for one
  /// all Perfect). On by default.
  bool get confetti => _confetti;
  bool _confetti = true;

  set confetti(bool value) {
    if (value == _confetti) return;
    _confetti = value;
    notifyListeners();
    _save();
  }

  /// Light or dark pages. Follows the phone's own setting by default.
  Appearance get appearance => _appearance;
  Appearance _appearance = Appearance.system;

  set appearance(Appearance value) {
    if (value == _appearance) return;
    _appearance = value;
    notifyListeners();
    _save();
  }

  /// Reads the saved preferences, if any. Until it completes (or if it
  /// fails) the defaults apply.
  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    try {
      final saved = await store.load();
      _colorNotesByJudgement = saved['colorNotesByJudgement'] as bool? ?? false;
      _showGreeting = saved['showGreeting'] as bool? ?? true;
      _confetti = saved['confetti'] as bool? ?? true;
      _appearance = Appearance.values.asNameMap()[saved['appearance']] ?? Appearance.system;
      notifyListeners();
    } catch (e) {
      debugPrint('Could not load settings: $e');
    }
  }

  void _save() {
    final store = _store;
    if (store == null) return;
    store.save({
      'colorNotesByJudgement': _colorNotesByJudgement,
      'showGreeting': _showGreeting,
      'confetti': _confetti,
      'appearance': _appearance.name,
    }).catchError((Object e) {
      debugPrint('Could not save settings: $e');
    });
  }
}

/// Keeps [AppSettings] between app launches.
abstract class SettingsStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> values);
}

/// Stores settings as a small JSON file in the app's documents directory.
class FileSettingsStore implements SettingsStore {
  const FileSettingsStore();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  @override
  Future<Map<String, Object?>> load() async {
    final file = await _file();
    if (!await file.exists()) return const {};
    return (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
  }

  @override
  Future<void> save(Map<String, Object?> values) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(values));
  }
}
