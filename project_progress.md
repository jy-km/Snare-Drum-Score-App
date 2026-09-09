# Project Progress

Tracks implementation status against the plan in `project_overview.md`. Updated as work progresses — check the "Last updated" line for freshness.

**Last updated**: 2026-09-09 (Milestone 1.5 complete — confirmed on Pixel 10 after fixing a startup-only playhead stutter)

## Status at a glance

| Milestone | Status |
|---|---|
| 1. Data model + MIDI codec + score entry + save/load | **Done** |
| 1.5. Real note-value staff notation + audio-synced playhead | **Done** — confirmed on Pixel 10 |
| 2. Practice screen (count-in, tempo cue, moving playhead) | Not started |
| 3. Mic capture + onset detection + scoring + replay | Not started |

## Key decisions (see `project_overview.md` for full context)

- Input method: microphone (acoustic), not MIDI input.
- Score file format: Standard MIDI File (.mid) via `dart_midi_pro`; velocity encodes accent/ghost-note dynamics.
- No anti-sharing restriction on saved files (dropped as a requirement).
- Platforms: Android/iOS only; desktop/web scaffolding to be removed from the repo.
- MVP note density: single-onset rhythm only; the "8 simultaneous notes" spec deferred to a later phase.
- ~~Rhythm entry UI: step-sequencer-style tap grid~~ — **superseded by Milestone 1.5**: real staff notation with explicit note values (1/4, 1/8, 1/16), since the tap-grid model had no concept of note duration and wouldn't generalize to pitched notes later. See Milestone 1.5 below.
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

## Milestone 1.5 — Real note-value staff notation + audio-synced playhead

Status: **Done**, confirmed on a Pixel 10 (real audio/visual sync judgment needs a human watching+listening in real time — screenshots and `dumpsys` can't substitute for that, only rule out gross bugs).

Scope: replaced the 4×4 tap-grid with real staff notation (1/4, 1/8, 1/16 note values, fixed pitch position matching the son's percussion-part convention), and replaced the discrete cell-highlight playhead with a continuously-moving, audio-synced vertical bar. See the plan file for the full design rationale (MuseScore/Sibelius precedent research, why proportional-not-idiomatic spacing was chosen, why the playhead architecture changed).

- [x] `lib/models/rhythm_score.dart` rewritten: `NoteValue` (quarter/eighth/sixteenth), `EventType` (rest/normal/accent), `RhythmEvent` (one duration token), `Measure` now an append-only `List<RhythmEvent>` instead of a fixed 16-slot array
- [x] `lib/services/midi_score_codec.dart` rewritten: encodes each event's *actual* notated duration as its MIDI note-off span (not a fixed short gate), so the decoder can recover real note values; gaps decode to rest tokens via largest-fit greedy matching
- [x] Bundled the Bravura SMuFL font (Steinberg, SIL Open Font License) via `curl` from its official GitHub repo — `assets/fonts/Bravura.otf` + `assets/fonts/Bravura-LICENSE.txt`, wired into `pubspec.yaml`
- [x] `lib/widgets/staff_notation_view.dart` (new): renders one measure as real notation — 5-line staff, treble clef, noteheads always on the fixed "C5" third space, precomposed SMuFL glyphs (single glyph per note = notehead+stem+flag combined, no manual beam/flag drawing needed), duration-proportional spacing so a note's x-position and the playhead's x-position share the exact same formula
- [x] `lib/screens/score_editor_screen.dart` rewritten: duration selector (1/4|1/8|1/16), type selector (Rest|Normal|Accent), append + backspace buttons (v1 is append-only, no mid-measure editing — confirmed scope with user), staff view replaces the old grid; wrapped body in `SingleChildScrollView` (the old `Spacer()`-based layout overflowed once the staff view's fixed height was added)
- [x] `lib/services/rhythm_player.dart` rewritten: `_renderSequence` now iterates variable-length events instead of a fixed 16-slot array; **playhead architecture redesigned** — a `Ticker`-driven local clock (via `SchedulerBinding.scheduleFrameCallback`) computes the displayed position every frame from wall-clock time, calibrated once from the first real `onPositionChanged` sample (not the moment `play()` was called, since there's buffering latency before audio is actually audible) and gently corrected against later samples to prevent drift — avoids per-frame platform-channel round-trips entirely, and moves continuously rather than jumping between discrete notes
- [x] Tests: `midi_score_codec_test.dart` rewritten (round-trip including a fully-complete measure with rests already in largest-fit form, a gap-to-rest-decomposition test — documented that only *complete* measures with rests already in largest-fit form round-trip to an identical event list, since silence alone can't distinguish "how a rest was subdivided" or "intentionally incomplete" from a MIDI file); `widget_test.dart` rewritten for the new duration/type/backspace UI — 7/7 passing, `flutter analyze` clean
- [x] Manual verification (Android emulator): treble clef + staff rendered correctly; entered accent quarter + 2 normal eighths + quarter rest — correct glyphs (individual flags per note, accent mark, rest symbol), correct proportional spacing, cursor positioned correctly; Play showed continuous smooth playhead motion (confirmed via consecutive frame screenshots) and correct ~19.7s duration for 8 measures at 100 BPM (verified via `dumpsys audio` timestamps, not wall-clock guessing — ADB round-trip overhead makes naive `sleep`-based timing unreliable on this emulator); Save/reload round-tripped correctly, including the expected trailing-rest auto-completion for an originally-incomplete measure
- [x] Manual verification (Pixel 10, real hardware): staff/clef rendering confirmed on real hardware too; user confirmed audio/visual sync is correct, with a residual "very tiny, almost negligible" unsmoothness at the very start of playback only (see bugs below)

**Two more real bugs found via user testing on the Pixel 10, both isolated to the first ~1 second of playback:**
1. **Glyph re-layout every frame.** `StaffNotationView`'s `_paintGlyph` created a brand-new `TextPainter` and called `.layout()` (font shaping) on *every* paint call. Playback's every-frame repaint (needed for smooth playhead motion) was redoing that shaping work for every note/rest/clef glyph, every frame — cost scales with how many glyphs are in the visible measure. Fixed by caching each glyph's laid-out `TextPainter` by `(glyph, fontSize)`; there are only a handful of distinct combinations in the whole app, so after the first paint ever, it's a cache hit forever. (This turned out not to be the dominant cause of the reported jank — see #2 — but is a real, worthwhile fix regardless.)
2. **The actual cause, found via temporary on-device logging** (confirmed with the user that denser-but-later measures were *not* janky, only ever the very start of playback, which ruled out #1 as the primary cause and pointed at something purely time-based): `rhythm_player.dart`'s position calibration was reacting to unreliable native position reports that only occur in roughly the first second after `play()`. Captured directly from the Pixel 10: the native player reports position as exactly `0` for ~400ms while buffering (each zero reading was dragging our calibration anchor forward, causing a visible catch-up jump once real data arrived), and separately, about a second in, one sample briefly *regressed* (637ms → 336ms — a real quirk in native reporting, not noise we introduced), which our correction dutifully followed, causing the displayed position to visibly move backward for a few frames. Fixed in `RhythmPlayer._onPositionSample`: don't calibrate off a reading below `_minStartupPosition` (20ms), and reject any sample that would move position backward (safe since we never seek during playback, so real position can only move forward). User confirmed this fixed it, with only a negligible residual flicker remaining.

**Lesson reinforced**: when a bug report includes "it's worse under condition X," verify that correlation before designing a fix around it — the user's own follow-up correction (a later, denser measure was *not* janky) is what redirected the investigation from "glyph rendering cost" to "startup-only timing issue," which turned out to be the real cause. Capturing actual on-device data (temporary logging + `flutter run`'s console output) beat further speculation.

## Milestone 2 — Practice screen (future)

Status: **Not started**

Scope narrowed by Milestone 1.5, which already delivered the audio-synced moving playhead: tempo count-in, visual tempo cue, and an independently adjustable practice tempo (distinct from the score's stored target tempo — see Key decisions), reusing `rhythm_player.dart`'s existing `tempoBpmOverride` parameter and Ticker-based playhead. No mic/detection — independently testable against saved scores.

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
