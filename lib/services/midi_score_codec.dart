import 'package:dart_midi_pro/dart_midi_pro.dart';

import '../models/rhythm_score.dart';

/// Converts between [RhythmScore] and Standard MIDI File bytes.
///
/// One note number represents every hit, on the GM percussion channel --
/// which note number depends on the score's [Instrument] (see
/// [InstrumentMidiNote.midiNoteNumber]). Velocity encodes accent/normal
/// dynamics directly instead of a separate flag. Each event is encoded with a
/// note-off at its actual notated duration (not a fixed short gate) so the
/// decoder can recover each event's real [NoteValue] on load; gaps between
/// notes decode to rest tokens.
///
/// Rests aren't MIDI events, so only the total silent duration of a gap
/// survives the round-trip, not how it was originally subdivided: a gap is
/// always reconstructed using the largest-fitting rest values first
/// (e.g. an eighth rest rather than two sixteenth rests; see
/// [_restsForGap]). Only measures entered with rests already in that
/// largest-fit form round-trip to an identical event list.
class MidiScoreCodec {
  static const int ticksPerQuarterNote = 480;
  static const int ticksPerUnit = ticksPerQuarterNote ~/ RhythmGrid.unitsPerQuarterNote;
  static const int drumChannel = 9;

  static const int _accentVelocityThreshold = 90;

  static List<int> encode(RhythmScore score) {
    final absoluteEvents = <_AbsoluteEvent>[
      _AbsoluteEvent(0, TrackNameEvent()..text = score.title),
      _AbsoluteEvent(
        0,
        SetTempoEvent()..microsecondsPerBeat = (60000000 / score.tempoBpm).round(),
      ),
      _AbsoluteEvent(
        0,
        TimeSignatureEvent()
          ..numerator = score.beatsPerMeasure
          ..denominator = score.beatUnit,
      ),
    ];

    final noteNumber = score.instrument.midiNoteNumber;

    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++) {
      final measure = score.measures[measureIndex];
      var cursorTick = measureIndex * score.unitsPerMeasure * ticksPerUnit;

      for (final event in measure.events) {
        final durationTicks = event.durationUnits * ticksPerUnit;
        if (!event.isRest) {
          absoluteEvents.add(
            _AbsoluteEvent(
              cursorTick,
              NoteOnEvent()
                ..noteNumber = noteNumber
                ..velocity = event.velocity
                ..channel = drumChannel,
            ),
          );
          absoluteEvents.add(
            _AbsoluteEvent(
              cursorTick + durationTicks,
              NoteOffEvent()
                ..noteNumber = noteNumber
                ..velocity = 0
                ..channel = drumChannel,
            ),
          );
        }
        cursorTick += durationTicks;
      }
    }

    absoluteEvents.sort((a, b) => a.tick.compareTo(b.tick));
    final endTick = score.measures.length * score.unitsPerMeasure * ticksPerUnit;
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
    final ticksPerUnitInFile = ticksPerBeat ~/ RhythmGrid.unitsPerQuarterNote;

    var title = 'Untitled';
    var tempoBpm = 100;
    var beatsPerMeasure = RhythmGrid.defaultBeatsPerMeasure;
    var beatUnit = RhythmGrid.defaultBeatUnit;
    var instrument = Instrument.snare;
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
      } else if (event is TimeSignatureEvent) {
        beatsPerMeasure = event.numerator;
        beatUnit = event.denominator;
      } else if (event is NoteOnEvent && event.velocity > 0) {
        pendingOnTick = absoluteTick;
        pendingVelocity = event.velocity;
        instrument = InstrumentMidiNote.fromMidiNoteNumber(event.noteNumber);
      } else if (event is NoteOffEvent && pendingOnTick != null) {
        intervals.add(_SoundingInterval(pendingOnTick, absoluteTick, pendingVelocity!));
        pendingOnTick = null;
        pendingVelocity = null;
      }
    }

    final unitsPerMeasure = beatsPerMeasure * (RhythmGrid.unitsPerWholeNote ~/ beatUnit);
    final measureLengthTicks = unitsPerMeasure * ticksPerUnitInFile;
    // `absoluteTick` now sits at the last event processed -- by construction
    // in `encode`, that's always the EndOfTrackEvent at exactly
    // `measures.length * measureLengthTicks`, so this recovers the original
    // (possibly user-grown-beyond-the-starting-8) measure count without
    // needing a dedicated meta-event for it.
    final measuresCount = (absoluteTick / measureLengthTicks).round().clamp(1, 1 << 20);
    final measures = List.generate(measuresCount, (measureIndex) {
      final measureStartTick = measureIndex * measureLengthTicks;
      final measureEndTick = measureStartTick + measureLengthTicks;
      final measureIntervals = intervals
          .where((i) => i.onTick >= measureStartTick && i.onTick < measureEndTick)
          .toList()
        ..sort((a, b) => a.onTick.compareTo(b.onTick));

      final events = <RhythmEvent>[];
      var cursorTick = measureStartTick;

      void fillGapUntil(int endTick) {
        if (endTick <= cursorTick) return;
        final startUnit = (cursorTick - measureStartTick) ~/ ticksPerUnitInFile;
        final gapUnits = (endTick - cursorTick) ~/ ticksPerUnitInFile;
        events.addAll(_restsForGap(startUnit, gapUnits));
      }

      for (final interval in measureIntervals) {
        fillGapUntil(interval.onTick);
        final durationUnits =
            ((interval.offTick - interval.onTick) / ticksPerUnitInFile).round();
        final value = _nearestNoteValue(durationUnits);
        final type =
            interval.velocity >= _accentVelocityThreshold ? EventType.accent : EventType.normal;
        events.add(RhythmEvent(value, type));
        cursorTick = interval.onTick + value.units * ticksPerUnitInFile;
      }

      fillGapUntil(measureEndTick);

      return Measure(events);
    });

    return RhythmScore(
      title: title,
      tempoBpm: tempoBpm,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
      instrument: instrument,
      measures: measures,
    );
  }

  static const _valuesLargestFirst = [
    NoteValue.quarter,
    NoteValue.eighth,
    NoteValue.eighthTriplet,
    NoteValue.sixteenth,
  ];

  static const _valuesTripletFirst = [
    NoteValue.eighthTriplet,
    NoteValue.quarter,
    NoteValue.eighth,
    NoteValue.sixteenth,
  ];

  static NoteValue _nearestNoteValue(int units) {
    for (final value in _valuesLargestFirst) {
      if (units >= value.units) return value;
    }
    return NoteValue.sixteenth;
  }

  /// Fills a [gapUnits]-long silence starting [startUnit] units into its
  /// measure with rests, largest-fitting values first -- the same approach
  /// real notation software uses to display unfilled measure space.
  ///
  /// A plain greedy pass isn't enough once triplets exist: the two-triplet
  /// gap before the last note of a triplet group is 8 units, and greedily
  /// taking an eighth rest (6) strands 2 units no rest value can fill. So
  /// this backtracks until the rests add up exactly. If nothing adds up (a
  /// gap of 1, 2 or 5 units, only possible as the unfilled tail of an
  /// incomplete measure), it fills as much of the gap as it can.
  static List<RhythmEvent> _restsForGap(int startUnit, int gapUnits) {
    for (var fillUnits = gapUnits; fillUnits > 0; fillUnits--) {
      final rests = <RhythmEvent>[];
      if (_fitRests(startUnit, fillUnits, rests, <int>{})) return rests;
    }
    return const [];
  }

  /// Appends rests totalling exactly [remaining] units to [rests], or leaves
  /// it untouched and returns false if no combination does. [deadEnds]
  /// remembers remainders already found unfillable (the position is implied
  /// by the remainder, so the remainder alone identifies the subproblem).
  static bool _fitRests(int position, int remaining, List<RhythmEvent> rests, Set<int> deadEnds) {
    if (remaining == 0) return true;
    if (deadEnds.contains(remaining)) return false;
    // Partway through a triplet group, finish the group with triplet rests
    // before falling back to the usual largest-first order.
    final midTriplet = position % NoteValue.sixteenth.units != 0;
    for (final value in midTriplet ? _valuesTripletFirst : _valuesLargestFirst) {
      if (value.units > remaining) continue;
      rests.add(RhythmEvent(value, EventType.rest));
      if (_fitRests(position + value.units, remaining - value.units, rests, deadEnds)) {
        return true;
      }
      rests.removeLast();
    }
    deadEnds.add(remaining);
    return false;
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
