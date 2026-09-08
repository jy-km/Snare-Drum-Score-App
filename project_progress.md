# Project Progress

Tracks implementation status against the plan in `project_overview.md`. Updated as work progresses — check the "Last updated" line for freshness.

**Last updated**: 2026-09-07 (Milestone 1 playback engine redesigned after user found real bugs testing on their own device)

## Status at a glance

| Milestone | Status |
|---|---|
| 1. Data model + MIDI codec + score entry + save/load | **Done** |
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

Status: **Done** (verified on Android emulator; iOS not yet tested)

Scope: create/edit an 8-measure snare rhythm on a tap grid, save to a local `.mid` file, reload it, and play it back audibly to verify correct entry. No mic/detection/scoring yet.

- [x] `lib/models/rhythm_score.dart` — `RhythmScore`, `Measure`, `Beat` domain model
- [x] `lib/services/midi_score_codec.dart` — `RhythmScore` ↔ Standard MIDI File bytes (via `dart_midi_pro`)
- [x] `lib/services/score_storage.dart` — save/list/load/delete `.mid` files via `path_provider`
- [x] `lib/services/click_sound.dart` — synthesized percussive click, normal/accent gain levels
- [x] `lib/services/rhythm_player.dart` — tempo-driven playback scheduler across all 8 measures + current-position stream for UI highlighting
- [x] `lib/screens/score_list_screen.dart` — list/create/open saved scores
- [x] `lib/screens/score_editor_screen.dart` — 4×4 step-sequencer grid per measure, numbered tab strip (1-8) for navigation, tempo/title fields, Play/Stop (with playing-cell highlight + auto-advancing tab), Save
- [x] Remove counter boilerplate from `lib/main.dart`; wire root to `ScoreListScreen`
- [x] `pubspec.yaml`: add `dart_midi_pro`, `path_provider`, `audioplayers`
- [x] Remove `windows/`, `macos/`, `linux/`, `web/` platform folders
- [x] Tests: `RhythmScore` → MIDI → `RhythmScore` round-trip; editor widget test — 4/4 passing (`flutter test`), `flutter analyze` clean
- [x] Manual verification (Android emulator): created an 8-measure rhythm, played it back (correct moving highlight, auto-advancing measure tabs, auto-stop at end), saved, navigated back to the list, reopened, and confirmed title/tempo/pattern all persisted exactly. Pulled the raw `.mid` file off the device and verified it's a well-formed Standard MIDI File byte-for-byte (correct `MThd`/`MTrk`, tempo meta-event = 100 BPM, note-on velocities 110/64 matching accent/normal).

**Playback architecture was redesigned after the user tested on their own device and found real bugs** the automated checks and my own on-device checks had missed:
1. `PlayerMode.lowLatency` (SoundPool) doesn't support `BytesSource` on Android at all — threw `PlatformException(AndroidAudioError, ...)`. Fixed by using the default `PlayerMode.mediaPlayer`.
2. Default `ReleaseMode.release` tears down each player's native resources after one playthrough — since the original design reused two long-lived players (retriggered via `seek()`+`resume()`), only the *first* hit on each player could ever work.
3. Default audio focus is exclusive (`gain`) — every `resume()` call requests focus, and since playback alternated between two players (normal/accent), each stole focus from the other (confirmed via `adb shell dumpsys audio`: `requestAudioFocus()` → `event: handleLoss` → `abandonAudioFocus()` in rapid succession), cutting hits off almost immediately.
4. **User-reported, and the actual reason #1-3 weren't a full fix**: even after fixing 1-3, a single isolated accent followed by rests produced a spurious echo, and the same pattern sounded different on repeat plays. Root cause: `seek()`+`resume()` are async platform-channel round-trips; when two calls on the same player overlapped in time (plausible whenever retriggers land close together, or a stale call from a previous Play press was still resolving), `audioplayers`' `seek()` — which waits for the *next* `onSeekComplete` event — could have its wait satisfied by the wrong event, firing an extra spurious `resume()`.

**Fix: stopped retriggering clips live entirely.** `rhythm_player.dart` now renders the whole 8-measure sequence to a single linear audio buffer up front (mixing each hit's click waveform into a silent buffer at its exact sample position — the same idea as bouncing a MIDI track to audio), then plays that one buffer once via a single `AudioPlayer`. No retrigger window exists anymore, so the result is deterministic by construction; the playhead highlight is now driven by the player's actual `onPositionChanged` stream instead of a separate Dart-side stopwatch, so it can't drift from the real audio either. Re-verified via `dumpsys audio`: exactly one `MediaPlayer` created per Play press, one continuous playthrough with zero focus-request/handleLoss churn.

**Lesson** (also saved to memory for future sessions): absence of exceptions plus correct UI behavior is not proof that audio plays correctly. Bugs 1-3 were only caught by the user actually listening on real hardware; the `dumpsys audio` technique (watching for focus churn and per-player lifecycle events) turned out to be the fastest objective way to diagnose without needing to hear it myself, and should be the standard check for any future audio-playback change here.

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
