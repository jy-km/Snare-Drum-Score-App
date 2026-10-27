import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rhythm_score.dart';
import '../services/rhythm_player.dart';
import '../services/score_storage.dart';
import '../services/track_sections.dart';
import '../widgets/app_theme.dart';
import '../widgets/beat_count.dart';
import '../widgets/staff_notation_view.dart';
import '../widgets/tap_tempo_button.dart';
import '../widgets/tempo_mark.dart';

class ScoreEditorScreen extends StatefulWidget {
  final String fileName;
  final RhythmScore initialScore;

  /// The track's sections, kept on the same music when measures are deleted
  /// (see [TrackSections.measureDeleted]). Null for a track with none to
  /// keep track of (e.g. a new one).
  final TrackSections? sections;

  /// Where the track is saved; replaceable so tests can use an in-memory one.
  final ScoreStorage? storage;

  const ScoreEditorScreen({
    super.key,
    required this.fileName,
    required this.initialScore,
    this.sections,
    this.storage,
  });

  @override
  State<ScoreEditorScreen> createState() => _ScoreEditorScreenState();
}

class _ScoreEditorScreenState extends State<ScoreEditorScreen> {
  late final ScoreStorage _storage = widget.storage ?? ScoreStorage();
  final _player = RhythmPlayer();

  late RhythmScore _score;
  late final TextEditingController _titleController;
  late final TextEditingController _tempoController;

  int _activeMeasure = 0;
  EventType _selectedType = EventType.normal;

  /// The flam, drag or roll given to notes entered next (and to the picked
  /// note).
  Ornament _selectedOrnament = Ornament.none;

  /// Measures deleted since the last save, in the order they were deleted
  /// (each index as it was at the time). Sections are moved to follow them
  /// only when the track is saved -- leaving without saving keeps both the
  /// track and its sections as they were.
  final _deletedMeasures = <int>[];

  /// The note or rest of the current measure picked by tapping it on the
  /// staff, if any. While one is picked, the length and type buttons change
  /// it and backspace removes it; otherwise they work at the end of the
  /// measure, as before.
  int? _selectedEvent;

  /// Set right after a crescendo or decrescendo is started at a note
  /// (measure index, event index): the next note tapped is where it goes
  /// to.
  (int, int)? _hairpinEndPendingFrom;

  /// Continuous position across the whole score, in [RhythmGrid] units.
  double? _playheadUnits;
  StreamSubscription<double?>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _titleController = TextEditingController(text: _score.title);
    _tempoController = TextEditingController(text: _score.tempoBpm.toString());
    _positionSubscription = _player.positionStream.listen((units) {
      setState(() {
        _playheadUnits = units;
        if (units != null) {
          _activeMeasure = _score.measureIndexAt(units);
        }
      });
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _player.dispose();
    _titleController.dispose();
    _tempoController.dispose();
    super.dispose();
  }

  int _readTempo() => int.tryParse(_tempoController.text) ?? _score.tempoBpm;

  static const _minTempoBpm = 20;
  static const _maxTempoBpm = 300;

  /// How far a finger travels per BPM while swiping the tempo.
  static const _tempoSwipePixelsPerBpm = 4.0;

  /// The tempo when a long press on the tempo number began, while the swipe
  /// that follows it is still going; null otherwise.
  int? _tempoAtSwipeStart;

  void _startTempoSwipe(LongPressStartDetails details) {
    HapticFeedback.selectionClick();
    setState(() => _tempoAtSwipeStart = _readTempo());
  }

  /// Swiping up raises the tempo and swiping down lowers it, measured from
  /// where the long press began.
  void _updateTempoSwipe(LongPressMoveUpdateDetails details) {
    final start = _tempoAtSwipeStart;
    if (start == null) return;
    final change = (-details.offsetFromOrigin.dy / _tempoSwipePixelsPerBpm).round();
    final tempo = (start + change).clamp(_minTempoBpm, _maxTempoBpm);
    if (tempo.toString() != _tempoController.text) {
      _tempoController.text = tempo.toString();
    }
  }

  void _endTempoSwipe() {
    if (_tempoAtSwipeStart == null) return;
    setState(() => _tempoAtSwipeStart = null);
  }

  /// A length button: changes the picked note's length, or adds a new
  /// note at the end when none is picked.
  void _enterValue(NoteValue value) {
    setState(() {
      final measure = _score.measures[_activeMeasure];
      final selected = _selectedEvent;
      final Measure updated;
      if (selected != null) {
        if (!measure.canReplace(selected, value)) return;
        updated = measure.replaceAt(
          selected,
          measure.events[selected].copyWith(
            value: value,
            type: _selectedType,
            ornament: _selectedOrnament,
          ),
        );
      } else {
        if (!measure.canAppend(value)) return;
        updated = measure.appendEvent(
          RhythmEvent(value, _selectedType, ornament: _selectedOrnament),
        );
      }
      _score = _score.copyWithMeasure(_activeMeasure, updated);
    });
  }

  /// A type button: sets the type for what's entered next, and changes the
  /// picked note's type if one is picked.
  void _selectType(EventType type) {
    setState(() {
      _selectedType = type;
      final selected = _selectedEvent;
      if (selected == null) return;
      final measure = _score.measures[_activeMeasure];
      final event = measure.events[selected];
      _score = _score.copyWithMeasure(
        _activeMeasure,
        measure.replaceAt(selected, event.copyWith(type: type, ornament: _selectedOrnament)),
      );
    });
  }

  /// A flam, drag or roll button: tapping the one that's on turns it off
  /// again.
  /// Like a type button, it sets what's entered next and changes the picked
  /// note if one is picked. A rest can't have one.
  void _toggleOrnament(Ornament ornament) {
    setState(() {
      _selectedOrnament = ornament == _selectedOrnament ? Ornament.none : ornament;
      final selected = _selectedEvent;
      if (selected == null) return;
      final measure = _score.measures[_activeMeasure];
      final event = measure.events[selected];
      _score = _score.copyWithMeasure(
        _activeMeasure,
        measure.replaceAt(selected, event.copyWith(ornament: _selectedOrnament)),
      );
    });
  }

  /// Removes the picked note (the notes after it move up), or the last one
  /// when none is picked.
  void _backspace() {
    setState(() {
      final removed = _selectedEvent ?? _score.measures[_activeMeasure].events.length - 1;
      if (removed >= 0) _clearHairpinEndFrom(_activeMeasure, removed);
      _hairpinEndPendingFrom = null;
      final measure = _score.measures[_activeMeasure];
      final selected = _selectedEvent;
      _score = _score.copyWithMeasure(
        _activeMeasure,
        selected != null ? measure.removeAt(selected) : measure.removeLast(),
      );
      _selectedEvent = null;
    });
  }

  /// A long press on backspace: empties the current measure, keeping its
  /// time signature. Offers an undo, since it can take a whole measure of
  /// notes with it.
  void _clearMeasure() {
    final measureIndex = _activeMeasure;
    final before = _score.measures[measureIndex];
    if (before.events.isEmpty) return;
    final cleared = Measure.empty(meter: before.meter);
    HapticFeedback.mediumImpact();
    setState(() {
      _score = _score.copyWithMeasure(measureIndex, cleared);
      _selectedEvent = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Measure ${measureIndex + 1} cleared'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // Only while the emptied measure is still there untouched --
              // not after it was written in, deleted or moved.
              if (!mounted ||
                  measureIndex >= _score.measures.length ||
                  !identical(_score.measures[measureIndex], cleared)) {
                return;
              }
              setState(() {
                _score = _score.copyWithMeasure(measureIndex, before);
                if (_activeMeasure == measureIndex) _selectedEvent = null;
              });
            },
          ),
        ),
      );
  }

  /// The note index (into [RhythmScore.notes]) of the note at [measure],
  /// [event], or null for a rest.
  int? _noteIndexOf(int measure, int event) {
    final index = _score.noteEventIndexes.indexOf((measure, event));
    return index < 0 ? null : index;
  }

  /// Replaces the event at [measure], [event] with [change] of it.
  void _changeEvent(int measure, int event, RhythmEvent Function(RhythmEvent) change) {
    final updated = _score.measures[measure];
    _score = _score.copyWithMeasure(
      measure,
      updated.replaceAt(event, change(updated.events[event])),
    );
  }

  /// Removes the end mark of the hairpin starting at [measure], [event], if
  /// it has one -- so it can't end some later hairpin instead.
  void _clearHairpinEndFrom(int measure, int event) {
    final note = _noteIndexOf(measure, event);
    if (note == null) return;
    for (final span in _score.hairpinSpans) {
      if (span.firstNote != note) continue;
      final (endMeasure, endEvent) = _score.noteEventIndexes[span.lastNote];
      if (_score.measures[endMeasure].events[endEvent].hairpinEnd) {
        _changeEvent(endMeasure, endEvent, (e) => e.copyWith(hairpinEnd: false));
      }
    }
  }

  /// A dynamic marking button: writes it at the picked note, or takes it
  /// off if it's already there.
  void _toggleDynamicMark(DynamicMark mark) {
    final selected = _selectedEvent;
    if (selected == null) return;
    setState(() {
      _changeEvent(
        _activeMeasure,
        selected,
        (event) => event.dynamicMark == mark
            ? event.copyWith(clearDynamicMark: true)
            : event.copyWith(dynamicMark: mark),
      );
    });
  }

  /// The crescendo or decrescendo button. At the picked note: starts one
  /// there (then the next note tapped is where it goes to), takes it off if
  /// it's already there, or turns one into the other. While waiting for
  /// the note it goes to, tapping it again leaves it running on to the next
  /// marking.
  void _toggleHairpin(Hairpin kind) {
    final selected = _selectedEvent;
    setState(() {
      if (_hairpinEndPendingFrom != null) {
        _hairpinEndPendingFrom = null;
        return;
      }
      if (selected == null) return;
      final current = _score.measures[_activeMeasure].events[selected].hairpinStart;
      if (current == kind) {
        _clearHairpinEndFrom(_activeMeasure, selected);
        _changeEvent(_activeMeasure, selected, (e) => e.copyWith(clearHairpinStart: true));
      } else if (current != null) {
        _changeEvent(_activeMeasure, selected, (e) => e.copyWith(hairpinStart: kind));
      } else {
        _changeEvent(_activeMeasure, selected, (e) => e.copyWith(hairpinStart: kind));
        _hairpinEndPendingFrom = (_activeMeasure, selected);
      }
    });
  }

  /// Ends the hairpin waiting for its end at the tapped note -- which has
  /// to be a note, at or after where the hairpin starts.
  void _endHairpinAt(int index) {
    final (fromMeasure, fromEvent) = _hairpinEndPendingFrom!;
    final from = _noteIndexOf(fromMeasure, fromEvent);
    final to = _noteIndexOf(_activeMeasure, index);
    if (from == null || to == null || to < from) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Pick a note at or after where it starts.')),
        );
      return;
    }
    setState(() {
      _clearHairpinEndFrom(fromMeasure, fromEvent);
      _changeEvent(_activeMeasure, index, (e) => e.copyWith(hairpinEnd: true));
      _hairpinEndPendingFrom = null;
      _selectedEvent = null;
    });
  }

  /// Picks the tapped note (showing its type on the type buttons), or drops
  /// the pick when the same note or empty space is tapped. Right after a
  /// crescendo or decrescendo is started, the tapped note is where it goes
  /// to instead.
  void _tapEvent(int? index) {
    if (_hairpinEndPendingFrom != null && index != null) {
      _endHairpinAt(index);
      return;
    }
    setState(() {
      if (index == null || index == _selectedEvent) {
        _selectedEvent = null;
        return;
      }
      _selectedEvent = index;
      final event = _score.measures[_activeMeasure].events[index];
      _selectedType = event.type;
      _selectedOrnament = event.ornament;
    });
  }

  void _goToMeasure(int index) {
    setState(() {
      _activeMeasure = index;
      _selectedEvent = null;
    });
  }

  /// Deletes the current measure, asking first if it has notes in it. The
  /// measures after it move up.
  Future<void> _deleteMeasure() async {
    final measureIndex = _activeMeasure;
    if (_score.measures.length <= 1) return;
    if (_score.measures[measureIndex].hasNotes) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete measure ${measureIndex + 1}?'),
          content: const Text('Its notes will be deleted too.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('delete_measure_confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (_player.isPlaying) await _player.stop();
    setState(() {
      _score = _score.removeMeasure(measureIndex);
      _deletedMeasures.add(measureIndex);
      _activeMeasure = measureIndex.clamp(0, _score.measures.length - 1);
      _selectedEvent = null;
    });
  }

  /// Sets the time signature from the measure being edited on: earlier
  /// measures keep theirs, and so does any later measure that already has
  /// notes (see [RhythmScore.withMeterFrom]). Says what it couldn't change,
  /// so the effect isn't a surprise.
  Future<void> _changeMeter(TimeSignature meter) async {
    final before = _score;
    final measureIndex = _activeMeasure;
    if (meter == before.measures[measureIndex].meter) return;
    if (_player.isPlaying) await _player.stop();
    final after = before.withMeterFrom(measureIndex, meter);
    setState(() {
      _score = after;
      _selectedEvent = null;
    });

    final notices = <String>[];
    final dropped =
        before.measures[measureIndex].events.length - after.measures[measureIndex].events.length;
    if (dropped > 0) {
      notices.add(
        'Removed the last $dropped ${dropped == 1 ? 'entry' : 'entries'} of '
        'measure ${measureIndex + 1}, which no longer fit in $meter.',
      );
    }
    final kept = [
      for (var index = measureIndex + 1; index < after.measures.length; index++)
        if (after.measures[index].meter != meter) index + 1,
    ];
    if (kept.isNotEmpty) {
      notices.add(
        '${kept.length == 1 ? 'Measure' : 'Measures'} ${kept.join(', ')} '
        'already ${kept.length == 1 ? 'has' : 'have'} notes and kept '
        '${kept.length == 1 ? 'its' : 'their'} time signature.',
      );
    }
    if (notices.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notices.join(' '))));
    }
  }

  /// Appends a new empty measure and jumps straight to it so the user can
  /// start entering notes immediately.
  void _addMeasure() {
    setState(() {
      _score = _score.appendMeasure();
      _activeMeasure = _score.measures.length - 1;
      _selectedEvent = null;
    });
  }

  Future<void> _changeInstrument(Instrument instrument) async {
    if (instrument == _score.instrument) return;
    if (_player.isPlaying) await _player.stop();
    setState(() {
      _score = _score.copyWith(instrument: instrument);
    });
  }

  /// Keeps the BPM number as it is: 150 stays 150, now counted in the new
  /// beat.
  Future<void> _changeTempoBeat(TempoBeat beat) async {
    if (beat == _score.tempoBeat) return;
    if (_player.isPlaying) await _player.stop();
    setState(() {
      _score = _score.copyWith(tempoBeat: beat);
    });
  }

  Future<void> _togglePlay() async {
    if (_player.isPlaying) {
      await _player.stop();
      setState(() {});
      return;
    }
    _score = _score.copyWith(tempoBpm: _readTempo());
    // Playback moves between measures, so a picked note would end up
    // pointing into the wrong one.
    setState(() => _selectedEvent = null);
    try {
      await _player.play(_score);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play: $e')));
      return;
    }
    if (!mounted) return;
    // Reflect "now playing" immediately -- otherwise the button only updates
    // once a real audio position sample arrives (see RhythmPlayer's startup
    // calibration), which can lag visibly behind the tap.
    setState(() {});
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    _score = _score.copyWith(title: title.isEmpty ? _score.title : title, tempoBpm: _readTempo());
    await _storage.save(widget.fileName, _score);
    final sections = widget.sections;
    if (sections != null && _deletedMeasures.isNotEmpty) {
      try {
        for (final deleted in _deletedMeasures) {
          await sections.measureDeleted(widget.fileName, deleted);
        }
      } catch (e) {
        debugPrint('Could not move the sections to follow deleted measures: $e');
      }
      _deletedMeasures.clear();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    final measure = _score.measures[_activeMeasure];
    final measureStarts = _score.measureStartUnits;
    final measureStartUnits = measureStarts[_activeMeasure];
    final playheadInMeasure =
        _playheadUnits != null &&
            _playheadUnits! >= measureStartUnits &&
            _playheadUnits! < measureStarts[_activeMeasure + 1]
        ? _playheadUnits! - measureStartUnits
        : null;
    final selected = _selectedEvent;
    bool canEnter(NoteValue value) =>
        selected != null ? measure.canReplace(selected, value) : measure.canAppend(value);

    // Printed where the time signature starts or changes, as in sheet music.
    final showTimeSignature =
        _activeMeasure == 0 || _score.measures[_activeMeasure - 1].meter != measure.meter;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Rhythm')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Written as sheet music writes a tempo: the beat note (which
                  // is also the button to change it), then "= 130".
                  _TempoBeatButton(beat: _score.tempoBeat, onSelect: _changeTempoBeat),
                  Text(' = ', style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(
                    width: 64,
                    child: Stack(
                      children: [
                        TextField(
                          key: const Key('tempo_field'),
                          controller: _tempoController,
                          keyboardType: TextInputType.number,
                          style: Theme.of(context).textTheme.titleMedium,
                          decoration: InputDecoration(
                            filled: _tempoAtSwipeStart != null,
                            fillColor: Theme.of(context).colorScheme.primaryContainer,
                          ),
                        ),
                        // Sits over the field without taking its taps. Its
                        // long press is a little shorter than the field's
                        // own (which would select the text), so this one
                        // always gets the gesture.
                        Positioned.fill(
                          child: RawGestureDetector(
                            key: const Key('tempo_swipe_area'),
                            behavior: HitTestBehavior.translucent,
                            gestures: {
                              LongPressGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                                    () => LongPressGestureRecognizer(
                                      duration:
                                          kLongPressTimeout - const Duration(milliseconds: 100),
                                    ),
                                    (recognizer) => recognizer
                                      ..onLongPressStart = _startTempoSwipe
                                      ..onLongPressMoveUpdate = _updateTempoSwipe
                                      ..onLongPressEnd = ((_) => _endTempoSwipe())
                                      ..onLongPressCancel = _endTempoSwipe,
                                  ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TapTempoButton(
                    key: const Key('editor_tap_tempo'),
                    minBpm: _minTempoBpm,
                    maxBpm: _maxTempoBpm,
                    onTempo: (bpm) => _tempoController.text = bpm.toString(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Wraps onto two lines on a narrow phone rather than overflowing.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  // Here rather than beside the tempo, which has the Tap
                  // button now and no room left on a narrow phone.
                  _MeterButton(meter: measure.meter, onSelect: _changeMeter),
                  _InstrumentButton(instrument: _score.instrument, onSelect: _changeInstrument),
                ],
              ),
              const SizedBox(height: 16),
              _MeasureTabStrip(
                measureCount: _score.measures.length,
                activeMeasure: _activeMeasure,
                onSelect: _goToMeasure,
                onAddMeasure: _addMeasure,
                onDeleteMeasure: _score.measures.length > 1 ? _deleteMeasure : null,
              ),
              const SizedBox(height: 12),
              StaffNotationView(
                key: const Key('editor_staff'),
                measure: measure,
                showTimeSignature: showTimeSignature,
                playheadUnits: playheadInMeasure,
                showCursor: !_player.isPlaying && selected == null,
                selectedEventIndex: selected,
                onTapEvent: _player.isPlaying ? null : _tapEvent,
                hairpins: _score.hairpinSegmentsIn(_activeMeasure),
              ),
              const SizedBox(height: 4),
              Text(filledBeatsText(measure), key: const Key('measure_fill_text')),
              Text(
                selected == null
                    ? 'Tap a note or rest on the staff to change it.'
                    : 'Note ${selected + 1} picked: tap a length, type or dynamic to change it, '
                          'or ⌫ to remove it. Tap it again to let go.',
                key: const Key('selection_hint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_hairpinEndPendingFrom != null)
                Text(
                  'Now tap the note it goes to -- or tap it again to let it run to the next '
                  'marking.',
                  key: const Key('hairpin_end_hint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.of(context).accent,
                  ),
                ),
              const SizedBox(height: 12),
              _TypeSelector(
                selected: _selectedType,
                onSelect: _selectType,
                selectedOrnament: _selectedOrnament,
                // A rest has no note to add a flam, drag or roll to.
                onToggleOrnament: _selectedType == EventType.rest ? null : _toggleOrnament,
              ),
              const SizedBox(height: 12),
              _NoteEntryStrip(
                children: [
                  _DurationButton(
                    keyName: 'duration_half',
                    label: '1/2',
                    enabled: canEnter(NoteValue.half),
                    onTap: () => _enterValue(NoteValue.half),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_quarter',
                    label: '1/4',
                    enabled: canEnter(NoteValue.quarter),
                    onTap: () => _enterValue(NoteValue.quarter),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_eighth',
                    label: '1/8',
                    enabled: canEnter(NoteValue.eighth),
                    onTap: () => _enterValue(NoteValue.eighth),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_sixteenth',
                    label: '1/16',
                    enabled: canEnter(NoteValue.sixteenth),
                    onTap: () => _enterValue(NoteValue.sixteenth),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_quarter_triplet',
                    label: '1/4³',
                    tooltip: 'Quarter-note triplet: three across two beats',
                    enabled: canEnter(NoteValue.quarterTriplet),
                    onTap: () => _enterValue(NoteValue.quarterTriplet),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_eighth_triplet',
                    label: '1/8³',
                    tooltip: 'Eighth-note triplet: three to a beat',
                    enabled: canEnter(NoteValue.eighthTriplet),
                    onTap: () => _enterValue(NoteValue.eighthTriplet),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_sixteenth_triplet',
                    label: '1/16³',
                    tooltip: 'Sixteenth-note triplet: six to a beat',
                    enabled: canEnter(NoteValue.sixteenthTriplet),
                    onTap: () => _enterValue(NoteValue.sixteenthTriplet),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('backspace'),
                    onPressed: measure.events.isEmpty ? null : _backspace,
                    onLongPress: _clearMeasure,
                    icon: const Icon(Icons.backspace_outlined),
                    tooltip: selected == null
                        ? 'Remove last (hold to clear the measure)'
                        : 'Remove picked note (hold to clear the measure)',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Below the length buttons, which are used far more.
              _DynamicsSelector(
                // Dynamics are written at a note: one has to be picked.
                picked: selected == null || measure.events[selected].isRest
                    ? null
                    : measure.events[selected],
                choosingEnd: _hairpinEndPendingFrom != null,
                onMark: _toggleDynamicMark,
                onHairpin: _toggleHairpin,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    key: const Key('play_button'),
                    onPressed: _togglePlay,
                    icon: Icon(_player.isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_player.isPlaying ? 'Stop' : 'Play'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('save_button'),
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A button labeled "Meter: #/#" -- the time signature of the measure being
/// edited -- that opens a popup list of every meter in both denominator
/// families ([RhythmGrid.beatUnits]) to choose from, rather than one button
/// per meter. Choosing one applies from that measure on (see
/// `_changeMeter`).
class _MeterButton extends StatelessWidget {
  final TimeSignature meter;
  final ValueChanged<TimeSignature> onSelect;

  const _MeterButton({required this.meter, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TimeSignature>(
      key: const Key('meter_button'),
      tooltip: 'Change the meter from this measure on',
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final unit in RhythmGrid.beatUnits) ...[
          if (unit != RhythmGrid.beatUnits.first) const PopupMenuDivider(),
          for (
            var beats = RhythmGrid.minBeatsPerMeasure;
            beats <= RhythmGrid.maxBeatsPerMeasureFor(unit);
            beats++
          )
            PopupMenuItem<TimeSignature>(
              key: Key('meter_option_${beats}_$unit'),
              value: TimeSignature(beats, unit),
              child: Text('$beats/$unit'),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('Meter: $meter'),
      ),
    );
  }
}

/// A button labeled "Instrument: `<name>`" that opens a popup list of every
/// [Instrument] to choose from, the same pattern as [_MeterButton].
/// Which note the tempo's BPM counts.
class _TempoBeatButton extends StatelessWidget {
  final TempoBeat beat;
  final ValueChanged<TempoBeat> onSelect;

  const _TempoBeatButton({required this.beat, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TempoBeat>(
      key: const Key('tempo_beat_button'),
      tooltip: 'Which note one beat of the tempo is',
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final option in TempoBeat.values)
          PopupMenuItem<TempoBeat>(
            key: Key('tempo_beat_option_${option.name}'),
            value: option,
            child: Text.rich(
              TextSpan(
                children: [
                  TempoMark.noteSpan(option, 16),
                  TextSpan(text: '   ${TempoMark.noteName(option)}'),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        key: Key('tempo_beat_${beat.name}'),
        padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(TempoMark.noteSpan(beat, 18)),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

class _InstrumentButton extends StatelessWidget {
  final Instrument instrument;
  final ValueChanged<Instrument> onSelect;

  const _InstrumentButton({required this.instrument, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Instrument>(
      key: const Key('instrument_button'),
      tooltip: 'Change instrument',
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final option in Instrument.values)
          PopupMenuItem<Instrument>(
            key: Key('instrument_option_${option.name}'),
            value: option,
            child: Text(_label(option)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('Instrument: ${_label(instrument)}'),
      ),
    );
  }

  String _label(Instrument instrument) {
    switch (instrument) {
      case Instrument.kick:
        return 'Kick';
      case Instrument.snare:
        return 'Snare';
      case Instrument.tambourine:
        return 'Tambourine';
    }
  }
}

/// A horizontally swipeable strip of fixed-size circular measure buttons,
/// with a same-sized "+" button at the end for appending a new measure. A
/// `Row` of `Expanded` buttons (the previous design) doesn't work once the
/// measure count is unbounded and user-grown -- it would keep squeezing
/// every button narrower forever instead of scrolling.
class _MeasureTabStrip extends StatefulWidget {
  final int measureCount;
  final int activeMeasure;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddMeasure;

  /// Deletes the current measure; null (button disabled) when there's only
  /// one left.
  final VoidCallback? onDeleteMeasure;

  const _MeasureTabStrip({
    required this.measureCount,
    required this.activeMeasure,
    required this.onSelect,
    required this.onAddMeasure,
    required this.onDeleteMeasure,
  });

  @override
  State<_MeasureTabStrip> createState() => _MeasureTabStripState();
}

class _MeasureTabStripState extends State<_MeasureTabStrip> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_MeasureTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.measureCount > oldWidget.measureCount) {
      // A measure was just appended -- scroll the strip so the new tab (and
      // the "+" button after it) are visible without the user swiping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _MeasureTabButton.size,
      child: ListView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        children: [
          for (var index = 0; index < widget.measureCount; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _MeasureTabButton(
                key: Key('measure_tab_$index'),
                label: '${index + 1}',
                selected: index == widget.activeMeasure,
                onTap: () => widget.onSelect(index),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _MeasureTabButton(
              key: const Key('measure_tab_add'),
              icon: Icons.add,
              selected: false,
              onTap: widget.onAddMeasure,
              tooltip: 'Add a measure',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _MeasureTabButton(
              key: const Key('measure_tab_delete'),
              icon: Icons.remove,
              selected: false,
              onTap: widget.onDeleteMeasure,
              tooltip: 'Delete this measure',
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasureTabButton extends StatelessWidget {
  static const double size = 40;

  final String? label;
  final IconData? icon;
  final bool selected;

  /// Null shows the button disabled.
  final VoidCallback? onTap;
  final String? tooltip;

  const _MeasureTabButton({
    super.key,
    this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    this.tooltip,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final button = SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          // The measure being edited is filled in ink.
          backgroundColor: selected ? palette.ink : null,
          foregroundColor: selected ? palette.paper : null,
        ),
        child: icon != null ? Icon(icon, size: 20) : Text(label!),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// The type buttons (one is always on), then the flam, drag and roll buttons
/// (each on or off, at most one at a time). On one line where they fit;
/// wrapping onto a second on a narrow phone.
class _TypeSelector extends StatelessWidget {
  final EventType selected;
  final ValueChanged<EventType> onSelect;
  final Ornament selectedOrnament;

  /// Null shows the flam, drag and roll buttons disabled.
  final ValueChanged<Ornament>? onToggleOrnament;

  const _TypeSelector({
    required this.selected,
    required this.onSelect,
    required this.selectedOrnament,
    required this.onToggleOrnament,
  });

  /// Narrower than a button's usual padding, so the row takes fewer lines.
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    // What's switched on is filled in ink.
    final palette = AppPalette.of(context);
    ButtonStyle style(bool on) => OutlinedButton.styleFrom(
      padding: _buttonPadding,
      backgroundColor: on ? palette.ink : null,
      foregroundColor: on ? palette.paper : null,
    );
    final toggleOrnament = onToggleOrnament;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (final type in EventType.values)
          OutlinedButton(
            key: Key('type_${type.name}'),
            onPressed: () => onSelect(type),
            style: style(type == selected),
            child: Text(_label(type)),
          ),
        for (final ornament in const [Ornament.flam, Ornament.drag, Ornament.roll])
          OutlinedButton(
            key: Key('ornament_${ornament.name}'),
            onPressed: toggleOrnament == null ? null : () => toggleOrnament(ornament),
            style: style(toggleOrnament != null && ornament == selectedOrnament),
            child: Text(_ornamentLabel(ornament)),
          ),
      ],
    );
  }

  String _ornamentLabel(Ornament ornament) {
    switch (ornament) {
      case Ornament.none:
        return 'None';
      case Ornament.flam:
        return 'Flam';
      case Ornament.drag:
        return 'Drag';
      case Ornament.roll:
        return 'Roll';
    }
  }

  String _label(EventType type) {
    switch (type) {
      case EventType.rest:
        return 'Rest';
      case EventType.normal:
        return 'Normal';
      case EventType.accent:
        return 'Accent';
      case EventType.marcato:
        return 'Marcato';
    }
  }
}

/// The row of note-entry buttons. Centered when it fits the screen width;
/// horizontally swipeable (like [_MeasureTabStrip]) when it doesn't, so every
/// button stays reachable on a narrow phone instead of overflowing.
class _NoteEntryStrip extends StatelessWidget {
  final List<Widget> children;

  const _NoteEntryStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('note_entry_strip'),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
        ),
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  final String keyName;
  final String label;
  final String? tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _DurationButton({
    required this.keyName,
    required this.label,
    this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final button = ElevatedButton(
      key: Key(keyName),
      onPressed: enabled ? onTap : null,
      // Keys to press, not the screen's main action: paper tiles edged in
      // ink, rather than the solid ink of the main buttons.
      style: ElevatedButton.styleFrom(
        // Narrower than a button's usual padding, so more of the row is on
        // screen before it has to be swiped.
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: palette.surface,
        foregroundColor: palette.ink,
        side: BorderSide(color: enabled ? palette.ink : palette.rule),
        textStyle: const TextStyle(
          fontFamily: displayFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      child: Text(label),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// The dynamics buttons -- pp to ff, then crescendo and decrescendo -- for
/// the [picked] note. With no note picked they're off: dynamics are written
/// at a note. A marking or hairpin the picked note has is filled in ink.
class _DynamicsSelector extends StatelessWidget {
  final RhythmEvent? picked;

  /// Waiting for the note a just-started hairpin goes to: its button stays
  /// on, to be tapped again to leave it running.
  final bool choosingEnd;
  final ValueChanged<DynamicMark> onMark;
  final ValueChanged<Hairpin> onHairpin;

  const _DynamicsSelector({
    required this.picked,
    required this.choosingEnd,
    required this.onMark,
    required this.onHairpin,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final note = picked;
    ButtonStyle style(bool on) => OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(44, 40),
      backgroundColor: on ? palette.ink : null,
      foregroundColor: on ? palette.paper : null,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final mark in DynamicMark.values)
          OutlinedButton(
            key: Key('dynamic_${mark.name}'),
            onPressed: note == null || choosingEnd ? null : () => onMark(mark),
            style: style(note?.dynamicMark == mark),
            child: Text(
              StaffNotationView.dynamicGlyph(mark),
              semanticsLabel: mark.name,
              style: const TextStyle(fontFamily: 'Bravura', fontSize: 26, height: 1),
            ),
          ),
        for (final kind in Hairpin.values)
          OutlinedButton(
            key: Key('hairpin_${kind.name}'),
            onPressed: note == null && !choosingEnd ? null : () => onHairpin(kind),
            style: style(note?.hairpinStart == kind),
            child: Text(kind == Hairpin.crescendo ? 'cresc. <' : 'decresc. >'),
          ),
      ],
    );
  }
}
