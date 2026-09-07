# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

This is a Flutter project scaffolded from the default `flutter create` counter-app template (see `lib/main.dart`, `test/widget_test.dart`). Despite the repo name (Snare Drum Score App), no domain-specific code has been written yet — the app is currently the stock Flutter starter. Treat `lib/main.dart` as a placeholder to be replaced, not as established architecture to preserve.

Target platforms are configured for Android, iOS, web, Windows, macOS, and Linux (see the corresponding platform directories), but only default platform boilerplate exists in each.

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
