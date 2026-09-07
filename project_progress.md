# Project Progress

Tracks implementation status against the plan in `project_overview.md`. Updated as work progresses — check the "Last updated" line for freshness.

**Last updated**: 2026-09-07

## Status at a glance

| Milestone | Status |
|---|---|
| 1. Data model + MIDI codec + score entry + save/load | Not started |
| 2. Practice screen (count-in, tempo cue, moving playhead) | Not started |
| 3. Mic capture + onset detection + scoring + replay | Not started |

## Key decisions (see `project_overview.md` for full context)

- Input method: microphone (acoustic), not MIDI input.
- Score file format: Standard MIDI File (.mid) via `dart_midi_pro`; velocity encodes accent/ghost-note dynamics.
- No anti-sharing restriction on saved files (dropped as a requirement).
- Platforms: Android/iOS only; desktop/web scaffolding to be removed from the repo.
- MVP note density: single-onset rhythm only; the "8 simultaneous notes" spec deferred to a later phase.
- Rhythm entry UI: step-sequencer-style tap grid, not notation-style entry. Each measure is a 4×4 grid (4 beats × sixteenth-note subdivisions). Cell tap cycles rest → normal hit → accent → rest (3 states; ghost notes deferred). Navigation between the 8 measures is a numbered tab strip (1-8), not swipe/scroll.
- Milestone 1 includes playback of the entered rhythm (Play/Stop button, synthesized click sound, no bundled audio sample to avoid licensing questions) so users can verify entry before Milestone 2's full practice mode exists.
- Tempo is two distinct concepts: the score's stored **target tempo** (used as-is for Milestone 1's verification playback) and an independently adjustable **practice tempo** (Milestone 2 only — starts below target, increases across attempts). `rhythm_player.dart` takes tempo as a parameter so Milestone 2 can reuse it without rework.

## Milestone 1 — Data model + score entry + save/load

Status: **Not started**

Scope: create/edit an 8-measure snare rhythm on a tap grid, save to a local `.mid` file, reload it, and play it back audibly to verify correct entry. No mic/detection/scoring yet.

- [ ] `lib/models/rhythm_score.dart` — `RhythmScore`, `Measure`, `Beat` domain model
- [ ] `lib/services/midi_score_codec.dart` — `RhythmScore` ↔ Standard MIDI File bytes (via `dart_midi_pro`)
- [ ] `lib/services/score_storage.dart` — save/list/load/delete `.mid` files via `path_provider`
- [ ] `lib/services/click_sound.dart` — synthesized percussive click, normal/accent gain levels
- [ ] `lib/services/rhythm_player.dart` — tempo-driven playback scheduler across all 8 measures + current-position stream for UI highlighting
- [ ] `lib/screens/score_list_screen.dart` — list/create/open saved scores
- [ ] `lib/screens/score_editor_screen.dart` — 4×4 step-sequencer grid per measure, numbered tab strip (1-8) for navigation, tempo/title fields, Play/Stop (with playing-cell highlight + auto-advancing tab), Save
- [ ] Remove counter boilerplate from `lib/main.dart`; wire root to `ScoreListScreen`
- [ ] `pubspec.yaml`: add `dart_midi_pro`, `path_provider`, `audioplayers`
- [ ] Remove `windows/`, `macos/`, `linux/`, `web/` platform folders
- [ ] Tests: `RhythmScore` → MIDI → `RhythmScore` round-trip; editor widget test
- [ ] Manual verification: create/save/reload on device or emulator; confirm `.mid` opens in an external MIDI tool; press Play and confirm audible rhythm matches entry (accents louder, rests silent)

## Milestone 2 — Practice screen (future)

Status: **Not started**

Scope: tempo count-in, visual tempo cue, moving playhead bar synced to a scheduled click track, and an independently adjustable practice tempo (distinct from the score's stored target tempo — see Key decisions). No mic/detection — independently testable against Milestone 1's saved scores.

- [ ] Not yet broken into tasks — will be detailed when Milestone 1 is done and this becomes current.

## Milestone 3 — Mic capture + onset detection + scoring + replay (future)

Status: **Not started**

Scope: capture mic audio via `flutter_sound`, hand-rolled onset detector (energy/spectral-flux peak picking), compare detected vs. expected onset times, compute a score, replay overlay showing timing/pitch deviation.

- [ ] Recommended: throwaway on-device spike to validate onset-detection accuracy before building UI around it
- [ ] Not yet broken into tasks — will be detailed when Milestone 2 is done and this becomes current

## Open questions (unresolved, not blocking Milestone 1)

- Note/rhythm entry UI details beyond the basic tap grid (e.g. rolls/flams notation for rudiments)
- Tempo range and scoring tolerance/threshold definitions (needed before Milestone 3)
- Time signatures beyond 4/4
