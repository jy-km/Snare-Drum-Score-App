# Project Progress

Tracks implementation status against the plan in `project_overview.md`. Updated as work progresses — check the "Last updated" line for freshness.

**Last updated**: 2026-09-09 (Milestone 2 complete — confirmed on Pixel 10 after fixing a count-in timing bug via a "Countdown Measure" redesign)

## Status at a glance

| Milestone | Status |
|---|---|
| 1. Data model + MIDI codec + score entry + save/load | **Done** |
| 1.5. Real note-value staff notation + audio-synced playhead | **Done** — confirmed on Pixel 10 |
| 2. Practice screen (count-in, tempo cue, moving playhead) | **Done** — confirmed on Pixel 10 |
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
- Milestone 2's practice screen plays **no rhythm audio at all** — the player performs the rhythm themselves on their instrument (Milestone 3 will listen via mic). The only audio is a 4-beat count-in, now modeled as a real "Countdown Measure" prepended to the same timeline the 8 real measures play on, so a single clock drives the whole run rather than a separate Timer racing a separate audio system. See Milestone 2 below.

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

## Milestone 2 — Practice screen

Status: **Done**, confirmed on a Pixel 10 (both the ring-buffer display logic and the count-in timing needed a real device and, for the final timing judgment, a real person tapping along in real time — screenshots and log evidence could confirm the mechanism but not the felt timing).

Scope: a new practice mode, distinct from `ScoreEditorScreen`'s verification playback. The device shows the player where they are in the score but does **not** play the rhythm's sound (Milestone 3's mic will listen instead) — an audible 4-beat count-in leads into a moving playhead across the score, with an independently adjustable practice tempo (never mutating the score's stored target tempo).

- [x] `lib/services/practice_slot_assignment.dart` (new): `PracticeSlotAssignment`, a ring-buffer tracker for 3 fixed on-screen slots (A/B/C). Slot *position* is fixed; slot *content* rotates — `slotForMeasure(idx) = idx % 3` decides both "which slot is active" and "which slot to refresh," and each refresh jumps a slot's content 2 measures ahead of the one it just finished showing, so a measure is visible for 2 full measures before it's due to be played (3 slots was chosen over 2 specifically for this margin — 2 slots would give only 1 measure of lookahead, judged too tight for denser rhythms). `measuresCount` is a constructor parameter (not hardcoded) so the practice screen could later extend the timeline (see the count-in redesign below) without changing this class's core logic.
- [x] `lib/screens/practice_screen.dart` (new): renders the 3 slots via the existing `StaffNotationView` unmodified, fades in a slot's new content via `AnimatedSwitcher` keyed on measure index, highlights the currently-playing slot, and blanks a slot instead of showing stale content once there's no measure left to refresh it with. A practice-tempo stepper is local UI state, initialized from the score's tempo but never written back to it.
- [x] `lib/screens/score_list_screen.dart`: added a `PracticeScreen` entry point per saved score.
- [x] Tests: `practice_slot_assignment_test.dart` (unit, drives the full measure-transition table including tail blanking), `practice_screen_test.dart` (widget tests for idle/tempo/count-in/playback/completion/stop) — all passing, `flutter analyze` clean.

**Two rounds of real bugs found via live testing on the Pixel 10** (screenshots + `adb shell input tap`/`screencap` to drive the app, `logcat` grepped for `MediaFocusControl`/`AudioTrack` lines to check audio-focus health — the same `dumpsys`-style technique from Milestone 1, just via `logcat` this time):

1. **3-slots-wide layout was unreadable.** The first version put all 3 measures side by side, each getting only ~1/3 of the screen width — proportional note spacing (the same formula `StaffNotationView` already used) meant notes were packed too close to read. User caught this immediately on the real device. Fixed by stacking the 3 slots full-width, one per row (like systems in sheet music), wrapped in a `SingleChildScrollView` since the stack no longer fits one screen height.

2. **Count-in clicks retriggered the same bug class Milestone 1 already fixed once.** The original count-in called `.play()` on the same `AudioPlayer` once per beat (4 calls, ~600ms apart) — back-to-back async platform-channel calls on one player race each other, exactly like `RhythmPlayer`'s old seek/resume retrigger bug. User reported "first two beats very short" or "first beat doesn't sound." First fix: pre-render all 4 clicks into one buffer, played with a single `.play()` call (mirrors `RhythmPlayer._renderSequence`'s "render once, play once" approach) — this fixed the click evenness, confirmed via `logcat` showing exactly one `requestAudioFocus`/`stop` cycle instead of four.
   - **That fix wasn't complete**: user still felt the gap between the last count-in beat and the first note of Measure 1 was shorter than a full beat. Root cause: the count-in's *visual* countdown ran on a plain Dart `Timer` starting the instant `.play()` was called, but real audio has ~hundreds of ms of startup latency before it's actually audible (the same latency `RhythmPlayer` documented and calibrated around in Milestone 1.5) — so the last click played audibly *later* than the Timer assumed, shortening the gap before playback began by exactly that latency.
   - **User's fix, implemented as-is**: instead of patching the calibration, model the count-in as a real "Countdown Measure" (4 quarter notes) prepended to the *same* timeline the 8 real measures play on, driven by one continuous `AnimationController` — not a separate Timer racing a separate audio system. The transition from the last count-in click into Measure 1 becomes ordinary continuous playhead motion across a measure boundary, identical in kind to any other measure-to-measure transition already proven smooth. The single clock is still calibrated once against the count-in click's real audio position (`AudioPlayer.onPositionChanged`, ignoring readings below 20ms exactly like `RhythmPlayer`'s `_minStartupPosition`) with a 1-second fallback in case no audio position ever arrives (e.g. no audio plugin under `flutter test`), so the fix doesn't depend on the platform channel being present to stay testable. `PracticeSlotAssignment.measuresCount` (see above) is what let this become a 9-measure timeline (count-in + 8 real measures) without changing the ring-buffer math itself.

**Lesson reinforced**: the same retrigger-bug shape (repeated `.play()` calls on a shared player) showed up a second time in a new context — worth treating "don't retrigger a shared audio player, render once and play once" as a standing rule for this codebase rather than something to rediscover per-feature. Separately, a bug fix that addresses the reported symptom (uneven clicks) isn't necessarily the *whole* bug (the timing-gap issue was a distinct root cause underneath) — the user's own architectural suggestion (unify the clock instead of patching the calibration) turned out to be a better fix than the calibration patch already in progress.

## Milestone 3 — Mic capture + onset detection + scoring + replay (future)

Status: **Not started**

Scope: capture mic audio via `flutter_sound`, hand-rolled onset detector (energy/spectral-flux peak picking), compare detected vs. expected onset times, compute a score, replay overlay showing timing/pitch deviation.

- [ ] Recommended: throwaway on-device spike to validate onset-detection accuracy before building UI around it
- [ ] Not yet broken into tasks — will be detailed when Milestone 2 is done and this becomes current

## Open questions (unresolved, not blocking Milestone 1)

- Note/rhythm entry UI details beyond the basic tap grid (e.g. rolls/flams notation for rudiments)
- Tempo range and scoring tolerance/threshold definitions (needed before Milestone 3)
- Time signatures beyond 4/4
