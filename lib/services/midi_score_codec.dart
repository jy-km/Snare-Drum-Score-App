import 'package:dart_midi_pro/dart_midi_pro.dart';

import '../models/rhythm_score.dart';

/// Converts between [RhythmScore] and Standard MIDI File bytes.
///
/// One note number represents the snare hit (General MIDI percussion note
/// 38, Acoustic Snare) on the GM percussion channel. Velocity encodes
/// accent/normal dynamics directly instead of a separate flag. Each event is
/// encoded with a note-off at its actual notated duration (not a fixed short
/// gate) so the decoder can recover each event's real [NoteValue] on load;
/// gaps between notes decode to rest tokens.
///
/// Rests aren't MIDI events, so only the total silent duration of a gap
/// survives the round-trip, not how it was originally subdivided: a gap is
/// always reconstructed using the largest-fitting rest values first
/// (e.g. an eighth rest rather than two sixteenth rests). Only measures
/// entered with rests already in that largest-fit form round-trip to an
/// identical event list.
class MidiScoreCodec {
  static const int ticksPerQuarterNote = 480;
  static const int ticksPerSixteenth = ticksPerQuarterNote ~/ RhythmGrid.subdivisionsPerBeat;
  static const int snareNoteNumber = 38;
  static const int drumChannel = 9;

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
      var cursorTick = measureIndex * RhythmGrid.unitsPerMeasure * ticksPerSixteenth;

      for (final event in measure.events) {
        final durationTicks = event.durationUnits * ticksPerSixteenth;
        if (!event.isRest) {
          absoluteEvents.add(
            _AbsoluteEvent(
              cursorTick,
              NoteOnEvent()
                ..noteNumber = snareNoteNumber
                ..velocity = event.velocity
                ..channel = drumChannel,
            ),
          );
          absoluteEvents.add(
            _AbsoluteEvent(
              cursorTick + durationTicks,
              NoteOffEvent()
                ..noteNumber = snareNoteNumber
                ..velocity = 0
                ..channel = drumChannel,
            ),
          );
        }
        cursorTick += durationTicks;
      }
    }

    absoluteEvents.sort((a, b) => a.tick.compareTo(b.tick));
    final endTick = score.measures.length * RhythmGrid.unitsPerMeasure * ticksPerSixteenth;
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
    final ticksPerSixteenthInFile = ticksPerBeat ~/ RhythmGrid.subdivisionsPerBeat;

    var title = 'Untitled';
    var tempoBpm = 100;
    var absoluteTick = 0;
    final intervals = <_SoundingInterval>[];
    int? pendingOnTick;
    int? pendingVelocity;

    for (final event in track) {
      absoluteTick += event.deltaTime;
      if (event is TrackNameEvent) {
        title = event.text;
      } else if (event is SetTempoEvent) {
        tempoBpm = (60000000 / event.microsecondsPerBeat).round();
      } else if (event is NoteOnEvent && event.velocity > 0) {
        pendingOnTick = absoluteTick;
        pendingVelocity = event.velocity;
      } else if (event is NoteOffEvent && pendingOnTick != null) {
        intervals.add(_SoundingInterval(pendingOnTick, absoluteTick, pendingVelocity!));
        pendingOnTick = null;
        pendingVelocity = null;
      }
    }

    final measureLengthTicks = RhythmGrid.unitsPerMeasure * ticksPerSixteenthInFile;
    final measures = List.generate(RhythmGrid.measuresCount, (measureIndex) {
      final measureStartTick = measureIndex * measureLengthTicks;
      final measureEndTick = measureStartTick + measureLengthTicks;
      final measureIntervals = intervals
          .where((i) => i.onTick >= measureStartTick && i.onTick < measureEndTick)
          .toList()
        ..sort((a, b) => a.onTick.compareTo(b.onTick));

      final events = <RhythmEvent>[];
      var cursorTick = measureStartTick;

      for (final interval in measureIntervals) {
        if (interval.onTick > cursorTick) {
          final gapUnits = (interval.onTick - cursorTick) ~/ ticksPerSixteenthInFile;
          events.addAll(_greedyRests(gapUnits));
        }
        final durationUnits =
            ((interval.offTick - interval.onTick) / ticksPerSixteenthInFile).round();
        final value = _nearestNoteValue(durationUnits);
        final type =
            interval.velocity >= _accentVelocityThreshold ? EventType.accent : EventType.normal;
        events.add(RhythmEvent(value, type));
        cursorTick = interval.onTick + value.sixteenthUnits * ticksPerSixteenthInFile;
      }

      if (cursorTick < measureEndTick) {
        final gapUnits = (measureEndTick - cursorTick) ~/ ticksPerSixteenthInFile;
        events.addAll(_greedyRests(gapUnits));
      }

      return Measure(events);
    });

    return RhythmScore(title: title, tempoBpm: tempoBpm, measures: measures);
  }

  static NoteValue _nearestNoteValue(int units) {
    if (units >= 4) return NoteValue.quarter;
    if (units >= 2) return NoteValue.eighth;
    return NoteValue.sixteenth;
  }

  /// Fills [units] sixteenth-note units with the largest-fitting rest values
  /// (quarter/eighth/sixteenth), same greedy approach real notation software
  /// uses to display unfilled measure space.
  static List<RhythmEvent> _greedyRests(int units) {
    final rests = <RhythmEvent>[];
    var remaining = units;
    for (final value in [NoteValue.quarter, NoteValue.eighth, NoteValue.sixteenth]) {
      while (remaining >= value.sixteenthUnits) {
        rests.add(RhythmEvent(value, EventType.rest));
        remaining -= value.sixteenthUnits;
      }
    }
    return rests;
  }
}

class _AbsoluteEvent {
  final int tick;
  final MidiEvent event;

  _AbsoluteEvent(this.tick, this.event);
}

class _SoundingInterval {
  final int onTick;
  final int offTick;
  final int velocity;

  _SoundingInterval(this.onTick, this.offTick, this.velocity);
}
