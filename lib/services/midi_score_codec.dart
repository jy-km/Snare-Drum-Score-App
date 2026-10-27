import 'package:dart_midi_pro/dart_midi_pro.dart';

import '../models/rhythm_score.dart';

/// Converts between [RhythmScore] and Standard MIDI File bytes.
///
/// One note number represents every hit, on the GM percussion channel --
/// which note number depends on the score's [Instrument] (see
/// [InstrumentMidiNote.midiNoteNumber]). Velocity encodes
/// marcato/accent/normal dynamics directly instead of a separate flag, and
/// a note's flam or drag is kept in its note-off's (otherwise unused)
/// release velocity. Each event is encoded with a
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
///
/// Dynamics (a note's dynamic marking and hairpin start or end) are text
/// events at the note's tick -- "dynamic:mf", "hairpin:crescendo",
/// "hairpin:end" -- which other programs show or ignore.
class MidiScoreCodec {
  static const int ticksPerQuarterNote = 480;
  static const int ticksPerUnit = ticksPerQuarterNote ~/ RhythmGrid.unitsPerQuarterNote;
  static const int drumChannel = 9;

  static const int _accentVelocityThreshold = 90;
  static const int _marcatoVelocityThreshold = 120;

  static List<int> encode(RhythmScore score) {
    final absoluteEvents = <_AbsoluteEvent>[
      _AbsoluteEvent(0, TrackNameEvent()..text = score.title),
      _AbsoluteEvent(
        0,
        // MIDI tempo is always per quarter note, whatever beat the score's
        // BPM counts; the beat itself goes in the time signature's
        // metronome click (see [_metronomeFor]).
        SetTempoEvent()
          ..microsecondsPerBeat =
              (60000000 / TempoBeat.quarter.convert(score.tempoBpm, score.tempoBeat)).round(),
      ),
    ];

    final noteNumber = score.instrument.midiNoteNumber;
    final measureStarts = score.measureStartUnits;

    for (var measureIndex = 0; measureIndex < score.measures.length; measureIndex++) {
      final measure = score.measures[measureIndex];
      var cursorTick = measureStarts[measureIndex] * ticksPerUnit;

      // A time signature at the start of the score, and again wherever it
      // changes -- the standard MIDI way of writing a meter change.
      if (measureIndex == 0 || measure.meter != score.measures[measureIndex - 1].meter) {
        absoluteEvents.add(
          _AbsoluteEvent(
            cursorTick,
            TimeSignatureEvent()
              ..numerator = measure.meter.beats
              ..denominator = measure.meter.beatUnit
              ..metronome = _metronomeFor(score.tempoBeat),
          ),
        );
      }

      for (final event in measure.events) {
        final durationTicks = event.durationUnits * ticksPerUnit;
        if (!event.isRest) {
          for (final text in _dynamicsTexts(event)) {
            absoluteEvents.add(_AbsoluteEvent(cursorTick, TextEvent()..text = text));
          }
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
                ..velocity = event.ornament.index
                ..channel = drumChannel,
            ),
          );
        }
        cursorTick += durationTicks;
      }
    }

    // Ties are kept in the order the events were added. That order matters:
    // a note's note-off and the next note's note-on often share a tick, and
    // the off must come first for the decoder to pair them correctly -- but
    // List.sort isn't stable (beyond a few dozen elements it may swap equal
    // ticks), so the tie has to be broken explicitly.
    final order = {for (var i = 0; i < absoluteEvents.length; i++) absoluteEvents[i]: i};
    absoluteEvents.sort((a, b) {
      final byTick = a.tick.compareTo(b.tick);
      return byTick != 0 ? byTick : order[a]!.compareTo(order[b]!);
    });
    final endTick = score.totalUnits * ticksPerUnit;
    absoluteEvents.add(_AbsoluteEvent(endTick, EndOfTrackEvent()));

    final events = <MidiEvent>[];
    var lastTick = 0;
    for (final absoluteEvent in absoluteEvents) {
      absoluteEvent.event.deltaTime = absoluteEvent.tick - lastTick;
      lastTick = absoluteEvent.tick;
      events.add(absoluteEvent.event);
    }

    final midiFile = MidiFile([
      events,
    ], MidiHeader(format: 0, numTracks: 1, ticksPerBeat: ticksPerQuarterNote));
    return MidiWriter().writeMidiToBuffer(midiFile);
  }

  static RhythmScore decode(List<int> bytes) {
    final midiFile = MidiParser().parseMidiFromBuffer(bytes);
    final track = midiFile.tracks.first;
    final ticksPerBeat = midiFile.header.ticksPerBeat ?? ticksPerQuarterNote;
    final ticksPerUnitInFile = ticksPerBeat ~/ RhythmGrid.unitsPerQuarterNote;

    var title = 'Untitled';
    var quarterBpm = 100.0;
    var tempoBeat = TempoBeat.quarter;
    // Each time signature and the tick it takes effect from. Files written
    // before meters could change mid-score have one, at tick 0; a file with
    // none is in 4/4.
    final meterChanges = <(int, TimeSignature)>[(0, TimeSignature.common)];
    var instrument = Instrument.snare;
    var absoluteTick = 0;
    final intervals = <_SoundingInterval>[];
    // Dynamics, by the tick of the note they're written at.
    final dynamicsTexts = <int, List<String>>{};
    int? pendingOnTick;
    int? pendingVelocity;

    for (final event in track) {
      absoluteTick += event.deltaTime;
      if (event is TrackNameEvent) {
        title = event.text;
      } else if (event is TextEvent) {
        (dynamicsTexts[absoluteTick] ??= []).add(event.text);
      } else if (event is SetTempoEvent) {
        quarterBpm = 60000000 / event.microsecondsPerBeat;
      } else if (event is TimeSignatureEvent) {
        final meter = TimeSignature(event.numerator, event.denominator);
        // One this app can't represent (e.g. 6/8 from another program) is
        // read as 4/4 rather than refusing the whole file.
        meterChanges.add((absoluteTick, meter.isValid ? meter : TimeSignature.common));
        if (absoluteTick == 0) tempoBeat = _tempoBeatFor(event.metronome);
      } else if (event is NoteOnEvent && event.velocity > 0) {
        // Files saved before `encode` broke same-tick ties explicitly can
        // have a note's note-on ahead of the previous note's note-off. A new
        // note starting therefore ends the one still sounding...
        if (pendingOnTick != null && absoluteTick > pendingOnTick) {
          intervals.add(
            _SoundingInterval(pendingOnTick, absoluteTick, pendingVelocity!, Ornament.none),
          );
        }
        pendingOnTick = absoluteTick;
        pendingVelocity = event.velocity;
        instrument = InstrumentMidiNote.fromMidiNoteNumber(event.noteNumber);
      } else if (event is NoteOffEvent && pendingOnTick == absoluteTick) {
        // ...and the late note-off that follows, on the very tick the new
        // note started, belongs to that earlier note -- this app never
        // writes a zero-length note.
      } else if (event is NoteOffEvent && pendingOnTick != null) {
        // A release velocity this app didn't write (from another program)
        // means no ornament.
        final ornament = event.velocity < Ornament.values.length
            ? Ornament.values[event.velocity]
            : Ornament.none;
        intervals.add(_SoundingInterval(pendingOnTick, absoluteTick, pendingVelocity!, ornament));
        pendingOnTick = null;
        pendingVelocity = null;
      }
    }

    TimeSignature meterAt(int tick) {
      var meter = meterChanges.first.$2;
      for (final (changeTick, changedMeter) in meterChanges) {
        if (changeTick <= tick) meter = changedMeter;
      }
      return meter;
    }

    // `absoluteTick` now sits at the last event processed -- by construction
    // in `encode`, that's always the EndOfTrackEvent at the very end of the
    // last measure, so laying measures out one after another up to it
    // recovers the original (possibly user-grown-beyond-the-starting-8)
    // measure count without needing a dedicated meta-event for it.
    final endTick = absoluteTick;
    final measures = <Measure>[];
    var measureStartTick = 0;
    do {
      final meter = meterAt(measureStartTick);
      final measureEndTick = measureStartTick + meter.units * ticksPerUnitInFile;
      measures.add(
        _decodeMeasure(intervals, meter, measureStartTick, measureEndTick, ticksPerUnitInFile),
      );
      measureStartTick = measureEndTick;
      // Stop once less than half a measure is left: what's left is rounding.
    } while (endTick - measureStartTick > meterAt(measureStartTick).units * ticksPerUnitInFile / 2);

    if (dynamicsTexts.isNotEmpty) {
      for (var index = 0; index < measures.length; index++) {
        measures[index] = _withDynamics(
          measures[index],
          index == 0 ? 0 : measures.take(index).fold(0, (sum, m) => sum + m.capacityUnits),
          ticksPerUnitInFile,
          dynamicsTexts,
        );
      }
    }

    return RhythmScore(
      title: title,
      tempoBpm: tempoBeat.convert(quarterBpm, TempoBeat.quarter).round(),
      tempoBeat: tempoBeat,
      instrument: instrument,
      measures: measures,
    );
  }

  static const _dynamicPrefix = 'dynamic:';
  static const _hairpinPrefix = 'hairpin:';
  static const _hairpinEndText = 'hairpin:end';

  /// The text events for [event]'s dynamics.
  static List<String> _dynamicsTexts(RhythmEvent event) => [
    if (event.dynamicMark case final mark?) '$_dynamicPrefix${mark.name}',
    if (event.hairpinStart case final kind?) '$_hairpinPrefix${kind.name}',
    if (event.hairpinEnd) _hairpinEndText,
  ];

  /// [measure] (starting [measureStartUnits] into the score) with the
  /// dynamics in [texts] put back on the notes at their ticks. Text this app
  /// didn't write is ignored.
  static Measure _withDynamics(
    Measure measure,
    int measureStartUnits,
    int ticksPerUnitInFile,
    Map<int, List<String>> texts,
  ) {
    var unit = measureStartUnits;
    final events = <RhythmEvent>[];
    for (final event in measure.events) {
      var marked = event;
      final atNote = event.isRest ? null : texts[unit * ticksPerUnitInFile];
      for (final text in atNote ?? const <String>[]) {
        if (text == _hairpinEndText) {
          marked = marked.copyWith(hairpinEnd: true);
        } else if (text.startsWith(_dynamicPrefix)) {
          final mark = DynamicMark.values.asNameMap()[text.substring(_dynamicPrefix.length)];
          if (mark != null) marked = marked.copyWith(dynamicMark: mark);
        } else if (text.startsWith(_hairpinPrefix)) {
          final kind = Hairpin.values.asNameMap()[text.substring(_hairpinPrefix.length)];
          if (kind != null) marked = marked.copyWith(hairpinStart: kind);
        }
      }
      events.add(marked);
      unit += event.durationUnits;
    }
    return Measure(events, meter: measure.meter);
  }

  /// MIDI clocks per metronome click -- 24 to a quarter note -- for a
  /// score whose BPM counts [beat].
  static int _metronomeFor(TempoBeat beat) => beat.units * 24 ~/ RhythmGrid.unitsPerQuarterNote;

  /// The beat a time signature's metronome click marks. Files saved before
  /// the beat could be chosen have 18 there, and other programs anything at
  /// all; those count quarter notes, as their BPM always did.
  static TempoBeat _tempoBeatFor(int metronome) => TempoBeat.values.firstWhere(
    (beat) => _metronomeFor(beat) == metronome,
    orElse: () => TempoBeat.quarter,
  );

  static Measure _decodeMeasure(
    List<_SoundingInterval> intervals,
    TimeSignature meter,
    int measureStartTick,
    int measureEndTick,
    int ticksPerUnitInFile,
  ) {
    final measureIntervals =
        intervals.where((i) => i.onTick >= measureStartTick && i.onTick < measureEndTick).toList()
          ..sort((a, b) => a.onTick.compareTo(b.onTick));

    final values = [
      for (final interval in measureIntervals)
        _nearestNoteValue(((interval.offTick - interval.onTick) / ticksPerUnitInFile).round()),
    ];

    final events = <RhythmEvent>[];
    var cursorTick = measureStartTick;

    // [besideQuarterTriplet]: whether a note next to the gap is a
    // quarter-note triplet, so the gap may belong to its group.
    void fillGapUntil(int endTick, {required bool besideQuarterTriplet}) {
      if (endTick <= cursorTick) return;
      final startUnit = (cursorTick - measureStartTick) ~/ ticksPerUnitInFile;
      final gapUnits = (endTick - cursorTick) ~/ ticksPerUnitInFile;
      events.addAll(_restsForGap(startUnit, gapUnits, besideQuarterTriplet));
    }

    for (final (index, interval) in measureIntervals.indexed) {
      final value = values[index];
      fillGapUntil(
        interval.onTick,
        besideQuarterTriplet:
            value == NoteValue.quarterTriplet ||
            (index > 0 && values[index - 1] == NoteValue.quarterTriplet),
      );
      final type = interval.velocity >= _marcatoVelocityThreshold
          ? EventType.marcato
          : interval.velocity >= _accentVelocityThreshold
          ? EventType.accent
          : EventType.normal;
      events.add(RhythmEvent(value, type, ornament: interval.ornament));
      cursorTick = interval.onTick + value.units * ticksPerUnitInFile;
    }

    fillGapUntil(
      measureEndTick,
      besideQuarterTriplet: values.isNotEmpty && values.last == NoteValue.quarterTriplet,
    );

    return Measure(events, meter: meter);
  }

  // The quarter-note triplet is left out of these: its rest is only used
  // beside a quarter-note triplet note (see [_fitRests]).
  static const _valuesLargestFirst = [
    NoteValue.half,
    NoteValue.quarter,
    NoteValue.eighth,
    NoteValue.eighthTriplet,
    NoteValue.sixteenth,
    NoteValue.sixteenthTriplet,
  ];

  static const _valuesTripletFirst = [
    NoteValue.eighthTriplet,
    NoteValue.quarter,
    NoteValue.eighth,
    NoteValue.sixteenth,
    NoteValue.sixteenthTriplet,
  ];

  static const _valuesSixteenthTripletFirst = [NoteValue.sixteenthTriplet, ..._valuesTripletFirst];

  static const _valuesQuarterTripletFirst = [NoteValue.quarterTriplet, ..._valuesLargestFirst];

  /// The note value exactly [units] long, or failing that (a file from
  /// another program) the longest one that fits in it.
  static NoteValue _nearestNoteValue(int units) {
    for (final value in NoteValue.values) {
      if (units == value.units) return value;
    }
    for (final value in _valuesLargestFirst) {
      if (units >= value.units) return value;
    }
    return NoteValue.sixteenthTriplet;
  }

  /// Fills a [gapUnits]-long silence starting [startUnit] units into its
  /// measure with rests, largest-fitting values first -- the same approach
  /// real notation software uses to display unfilled measure space.
  ///
  /// A plain greedy pass isn't enough once triplets exist: the two-triplet
  /// gap before the last note of a triplet group is 8 units, and greedily
  /// taking an eighth rest (6) strands 2 units no rest value can fill. So
  /// this backtracks until the rests add up exactly. A half rest is only
  /// used on a half-note boundary of the measure (beats 1 and 3 of 4/4), as
  /// in printed music; anywhere else the same silence is quarter rests. If nothing adds up (a
  /// gap of 1 unit, only possible as the unfilled tail of an incomplete
  /// measure), it fills as much of the gap as it can.
  ///
  /// A silence can often be written more than one way (two triplet-eighth
  /// rests last as long as one triplet-quarter rest). A triplet-quarter
  /// rest is only chosen with [besideQuarterTriplet], where the silence
  /// most likely belongs to that note's group.
  static List<RhythmEvent> _restsForGap(int startUnit, int gapUnits, bool besideQuarterTriplet) {
    // Sixteenth-triplet rests are a last resort for a silence that starts
    // where a longer rest could: without them a silence is written just as
    // it was before they existed (an 8-unit one as two triplet-eighth rests,
    // not an eighth rest and a sixteenth-triplet one).
    final startsOnCoarserGrid =
        startUnit % NoteValue.sixteenth.units == 0 ||
        startUnit % NoteValue.eighthTriplet.units == 0;
    for (var fillUnits = gapUnits; fillUnits > 0; fillUnits--) {
      for (final sixteenthTriplets in startsOnCoarserGrid ? const [false, true] : const [true]) {
        final rests = <RhythmEvent>[];
        if (_fitRests(
          startUnit,
          fillUnits,
          rests,
          <int>{},
          besideQuarterTriplet,
          sixteenthTriplets,
        )) {
          return rests;
        }
      }
    }
    return const [];
  }

  /// Appends rests totalling exactly [remaining] units to [rests], or leaves
  /// it untouched and returns false if no combination does. [deadEnds]
  /// remembers remainders already found unfillable (the position is implied
  /// by the remainder, so the remainder alone identifies the subproblem).
  static bool _fitRests(
    int position,
    int remaining,
    List<RhythmEvent> rests,
    Set<int> deadEnds,
    bool besideQuarterTriplet,
    bool sixteenthTriplets,
  ) {
    if (remaining == 0) return true;
    if (deadEnds.contains(remaining)) return false;
    // Partway through a triplet group, finish the group with triplet rests
    // (of the group's own length) before falling back to the usual
    // largest-first order.
    final positionInHalf = position % NoteValue.half.units;
    final List<NoteValue> order;
    if (besideQuarterTriplet &&
        positionInHalf % NoteValue.quarterTriplet.units == 0 &&
        !(positionInHalf == 0 && remaining >= NoteValue.half.units)) {
      order = _valuesQuarterTripletFirst;
    } else if (position % NoteValue.sixteenth.units == 0) {
      order = _valuesLargestFirst;
    } else if (position % NoteValue.eighthTriplet.units == 0) {
      order = _valuesTripletFirst;
    } else {
      order = _valuesSixteenthTripletFirst;
    }
    for (final value in order) {
      if (value.units > remaining) continue;
      if (value == NoteValue.sixteenthTriplet && !sixteenthTriplets) continue;
      if (value == NoteValue.half && position % NoteValue.half.units != 0) continue;
      rests.add(RhythmEvent(value, EventType.rest));
      if (_fitRests(
        position + value.units,
        remaining - value.units,
        rests,
        deadEnds,
        besideQuarterTriplet,
        sixteenthTriplets,
      )) {
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
  final Ornament ornament;

  _SoundingInterval(this.onTick, this.offTick, this.velocity, this.ornament);
}
