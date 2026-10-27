# CLAUDE.md

## Commands

Standard Flutter CLI, run from the repo root.

- Install dependencies: `flutter pub get`
- Run the app (device/emulator or `-d chrome` / `-d windows` for desktop/web): `flutter run`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/widget_test.dart`
- Static analysis (lint): `flutter analyze`
- Format code: `dart format .`
- Build a release (example: Windows): `flutter build windows`

## Linting

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no project-specific rule overrides. The `analyzer.exclude` list omits `build/**` and all platform directories (`android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`) from analysis — only `lib/` and `test/` are linted.

## Environment

- Dart SDK constraint: `^3.13.2` (see `pubspec.yaml`)
- No state management, routing, or networking packages are added yet — only `cupertino_icons` beyond the Flutter SDK itself.

## Project progress

Whenever a new session start, read project_overview.md to understand what this project is about. And check project_progress.md to know the current status. Whenever there is a meaningful progress, update project_progress.md.