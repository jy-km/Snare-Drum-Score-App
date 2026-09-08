import 'package:dart_midi_pro/dart_midi_pro.dart';

import '../models/rhythm_score.dart';

/// Converts between [RhythmScore] and Standard MIDI File bytes.
///
/// One note number represents the snare hit (General MIDI percussion note
/// 38, Acoustic Snare) on the GM percussion channel. Velocity encodes
/// accent/normal dynamics directly instead of a separate flag. Tempo and
/// time signature ride on standard MIDI meta-events.
class MidiScoreCodec {
  static const int ticksPerQuarterNote = 480;
  static const int ticksPerCell = ticksPerQuarterNote ~/ RhythmGrid.subdivisionsPerBeat;
  static const int snareNoteNumber = 38;
  static const int drumChannel = 9;

  /// Short gate length so note-off always lands before the next cell
  /// (ticksPerCell) even at the fastest supported subdivision.
  static const int noteDurationTicks = ticksPerCell ~/ 2;

  static const int _accentVelocityThreshold = 90;

  static List<int> encode(RhythmScore score) {
    final absoluteEvents = <_AbsoluteEvent>[
      _AbsoluteEvent(0, TrackNameEvent()..text = score.title),
      _AbsoluteEvent(
        0,
        SetTempoEvent()..microsecondsPerBeat = (60000000 / score.tempoBpm).round(),
      ),
      _AbsoluteEvent(0, TimeSignatureEvent()..numerator = 4..denominator = 4),
    ];

    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++) {
      final measure = score.measures[measureIndex];
      for (var cellIndex = 0; cellIndex < measure.beats.length; cellIndex++) {
        final beat = measure.beats[cellIndex];
        if (beat.isRest) continue;

        final startTick =
            (measureIndex * RhythmGrid.cellsPerMeasure + cellIndex) * ticksPerCell;
        absoluteEvents.add(
          _AbsoluteEvent(
            startTick,
            NoteOnEvent()
              ..noteNumber = snareNoteNumber
              ..velocity = beat.velocity
              ..channel = drumChannel,
          ),
        );
        absoluteEvents.add(
          _AbsoluteEvent(
            startTick + noteDurationTicks,
            NoteOffEvent()
              ..noteNumber = snareNoteNumber
              ..velocity = 0
              ..channel = drumChannel,
          ),
        );
      }
    }

    absoluteEvents.sort((a, b) => a.tick.compareTo(b.tick));
    final endTick = score.measures.length * RhythmGrid.cellsPerMeasure * ticksPerCell;
    absoluteEvents.add(_AbsoluteEvent(endTick, EndOfTrackEvent()));

    final events = <MidiEvent>[];
    var lastTick = 0;
    for (final absoluteEvent in absoluteEvents) {
      absoluteEvent.event.deltaTime = absoluteEvent.tick - lastTick;
      lastTick = absoluteEvent.tick;
      events.add(absoluteEvent.event);
    }

    final midiFile = MidiFile(
      [events],
      MidiHeader(format: 0, numTracks: 1, ticksPerBeat: ticksPerQuarterNote),
    );
    return MidiWriter().writeMidiToBuffer(midiFile);
  }

  static RhythmScore decode(List<int> bytes) {
    final midiFile = MidiParser().parseMidiFromBuffer(bytes);
    final track = midiFile.tracks.first;
    final ticksPerBeat = midiFile.header.ticksPerBeat ?? ticksPerQuarterNote;
    final ticksPerCellInFile = ticksPerBeat ~/ RhythmGrid.subdivisionsPerBeat;

    var title = 'Untitled';
    var tempoBpm = 100;
    var absoluteTick = 0;
    final hitVelocityByCell = <int, int>{};

    for (final event in track) {
      absoluteTick += event.deltaTime;
      if (event is TrackNameEvent) {
        title = event.text;
      } else if (event is SetTempoEvent) {
        tempoBpm = (60000000 / event.microsecondsPerBeat).round();
      } else if (event is NoteOnEvent && event.velocity > 0) {
        final cellIndex = (absoluteTick / ticksPerCellInFile).round();
        hitVelocityByCell[cellIndex] = event.velocity;
      }
    }

    final measures = List.generate(RhythmGrid.measuresCount, (measureIndex) {
      final beats = List.generate(RhythmGrid.cellsPerMeasure, (cellInMeasure) {
        final cellIndex = measureIndex * RhythmGrid.cellsPerMeasure + cellInMeasure;
        final velocity = hitVelocityByCell[cellIndex];
        if (velocity == null) return Beat.rest;
        return Beat(
          velocity >= _accentVelocityThreshold ? BeatState.accent : BeatState.normal,
        );
      });
      return Measure(beats);
    });

    return RhythmScore(title: title, tempoBpm: tempoBpm, measures: measures);
  }
}

class _AbsoluteEvent {
  final int tick;
  final MidiEvent event;

  _AbsoluteEvent(this.tick, this.event);
}
