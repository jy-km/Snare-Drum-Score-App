# Project Overview

## Final Objective

Build an Android/iOS app to help musicians practice music.

## Usage Example

A piano player has been practicing a piece for some time but consistently makes mistakes in a certain part of it. They want to practice only that part, starting from a slow tempo and working up to the target tempo.

1. Enter the part of the music score to practice.
2. Set a slow tempo and press Start.
3. The app shows a visual cue for the tempo, then counts down 4, 3, 2, 1.
4. A bar moves across the music score, and the player plays along with it.
5. After the part finishes, the app scores how correctly the part was played.
6. The app can replay the player's performance overlaid on the score, showing which notes were most off in pitch and/or rhythm from what was expected.
7. Once the score is satisfying, the player increases the tempo and repeats the process until they can comfortably play the part at the target tempo.

## Requirements

- Must be able to take in 8 measures of a music score (can be increased later).
- Must have an easy-to-use UI for entering notes.
- Must distinguish notes played at up to 10 notes per second.
- After notes are entered, the app must be able to play the score's sound with a bar moving across the score in sync.
- Must recognize up to 8 notes played by the device at a single point in time (can be relaxed or increased).
- An entered score must be savable to a file, and a saved score file must be loadable back into the app.
- Tempo is two distinct concepts, not one: the score's stored **target tempo** (what the piece is meant to be played at), and an independently adjustable **practice tempo** used during a practice session, which the user deliberately sets below the target and increases across repeated attempts until they can comfortably play at the target tempo.
- Score files are stored in the Standard MIDI File (.mid) format, for extensibility (interop with other MIDI tools, and a natural path to pitched-note support later). At 8 measures, sharing a file isn't considered a meaningful license risk, so no anti-sharing restriction is required. Optional future protection (e.g., encrypting the file at rest) may be added later if needed, but is not a current requirement.

## Project Plan

- Because full music note recognition is hard, start with rhythm only (e.g., snare drum practice).
- Once the app works well for snare drum (rhythm-only), extend it to handle pitched notes.

## Decisions Made

- Input method: microphone (acoustic), not MIDI input for detection.
- MVP note density: single-onset rhythm stream only (up to 10/sec); the "8 simultaneous notes" spec is deferred to a later multi-instrument/chord phase.
- Score file format: Standard MIDI File (.mid), via a pure-Dart MIDI library (e.g. `dart_midi_pro`).
- Target platforms: Android/iOS only; desktop/web scaffolding in this repo is to be removed.

## Open Questions / Risks

These are not yet resolved:

- Note/rhythm entry UI: tap-based grid, staff notation editor, or import from an existing format.
- Tempo range, time signature(s), and scoring tolerance/threshold definitions.
- Feasibility of real-time detection at 10 notes/sec with up to 8 simultaneous notes on typical phone hardware/mic (relevant once the app extends beyond single-instrument rhythm).
