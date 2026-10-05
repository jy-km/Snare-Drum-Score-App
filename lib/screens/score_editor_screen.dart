import 'dart:async';

import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/rhythm_player.dart';
import '../services/score_storage.dart';
import '../widgets/staff_notation_view.dart';

class ScoreEditorScreen extends StatefulWidget {
  final String fileName;
  final RhythmScore initialScore;

  const ScoreEditorScreen({
    super.key,
    required this.fileName,
    required this.initialScore,
  });

  @override
  State<ScoreEditorScreen> createState() => _ScoreEditorScreenState();
}

class _ScoreEditorScreenState extends State<ScoreEditorScreen> {
  final _storage = ScoreStorage();
  final _player = RhythmPlayer();

  late RhythmScore _score;
  late final TextEditingController _titleController;
  late final TextEditingController _tempoController;

  int _activeMeasure = 0;
  EventType _selectedType = EventType.normal;

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

  void _appendEvent(NoteValue value) {
    setState(() {
      final measure = _score.measures[_activeMeasure];
      if (!measure.canAppend(value)) return;
      final updated = measure.appendEvent(RhythmEvent(value, _selectedType));
      _score = _score.copyWithMeasure(_activeMeasure, updated);
    });
  }

  void _backspace() {
    setState(() {
      final measure = _score.measures[_activeMeasure];
      _score = _score.copyWithMeasure(_activeMeasure, measure.removeLast());
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
    setState(() => _score = after);

    final notices = <String>[];
    final dropped = before.measures[measureIndex].events.length -
        after.measures[measureIndex].events.length;
    if (dropped > 0) {
      notices.add('Removed the last $dropped ${dropped == 1 ? 'entry' : 'entries'} of '
          'measure ${measureIndex + 1}, which no longer fit in $meter.');
    }
    final kept = [
      for (var index = measureIndex + 1; index < after.measures.length; index++)
        if (after.measures[index].meter != meter) index + 1,
    ];
    if (kept.isNotEmpty) {
      notices.add('${kept.length == 1 ? 'Measure' : 'Measures'} ${kept.join(', ')} '
          'already ${kept.length == 1 ? 'has' : 'have'} notes and kept '
          '${kept.length == 1 ? 'its' : 'their'} time signature.');
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
    });
  }

  Future<void> _changeInstrument(Instrument instrument) async {
    if (instrument == _score.instrument) return;
    if (_player.isPlaying) await _player.stop();
    setState(() {
      _score = _score.copyWith(instrument: instrument);
    });
  }

  Future<void> _togglePlay() async {
    if (_player.isPlaying) {
      await _player.stop();
      setState(() {});
      return;
    }
    _score = _score.copyWith(tempoBpm: _readTempo());
    setState(() {});
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
    _score = _score.copyWith(
      title: title.isEmpty ? _score.title : title,
      tempoBpm: _readTempo(),
    );
    await _storage.save(widget.fileName, _score);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    final measure = _score.measures[_activeMeasure];
    final measureStarts = _score.measureStartUnits;
    final measureStartUnits = measureStarts[_activeMeasure];
    final playheadInMeasure = _playheadUnits != null &&
            _playheadUnits! >= measureStartUnits &&
            _playheadUnits! < measureStarts[_activeMeasure + 1]
        ? _playheadUnits! - measureStartUnits
        : null;
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
                  const Text('Tempo (BPM): '),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _tempoController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const Spacer(),
                  _MeterButton(
                    meter: measure.meter,
                    onSelect: _changeMeter,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InstrumentButton(
                    instrument: _score.instrument,
                    onSelect: _changeInstrument,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MeasureTabStrip(
                measureCount: _score.measures.length,
                activeMeasure: _activeMeasure,
                onSelect: (index) => setState(() => _activeMeasure = index),
                onAddMeasure: _addMeasure,
              ),
              const SizedBox(height: 12),
              StaffNotationView(
                measure: measure,
                showTimeSignature: showTimeSignature,
                playheadUnits: playheadInMeasure,
                showCursor: !_player.isPlaying,
              ),
              const SizedBox(height: 4),
              Text('${measure.filledUnits}/${measure.capacityUnits} units filled'),
              const SizedBox(height: 12),
              _TypeSelector(
                selected: _selectedType,
                onSelect: (type) => setState(() => _selectedType = type),
              ),
              const SizedBox(height: 12),
              _NoteEntryStrip(
                children: [
                  _DurationButton(
                    keyName: 'duration_quarter',
                    label: '1/4',
                    enabled: measure.canAppend(NoteValue.quarter),
                    onTap: () => _appendEvent(NoteValue.quarter),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_eighth',
                    label: '1/8',
                    enabled: measure.canAppend(NoteValue.eighth),
                    onTap: () => _appendEvent(NoteValue.eighth),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_sixteenth',
                    label: '1/16',
                    enabled: measure.canAppend(NoteValue.sixteenth),
                    onTap: () => _appendEvent(NoteValue.sixteenth),
                  ),
                  const SizedBox(width: 8),
                  _DurationButton(
                    keyName: 'duration_eighth_triplet',
                    label: 'Triplet',
                    enabled: measure.canAppend(NoteValue.eighthTriplet),
                    onTap: () => _appendEvent(NoteValue.eighthTriplet),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('backspace'),
                    onPressed: measure.events.isEmpty ? null : _backspace,
                    icon: const Icon(Icons.backspace_outlined),
                    tooltip: 'Remove last',
                  ),
                ],
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
                  ElevatedButton.icon(
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
          for (var beats = RhythmGrid.minBeatsPerMeasure;
              beats <= RhythmGrid.maxBeatsPerMeasureFor(unit);
              beats++)
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('Meter: $meter'),
      ),
    );
  }
}

/// A button labeled "Instrument: `<name>`" that opens a popup list of every
/// [Instrument] to choose from, the same pattern as [_MeterButton].
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
          borderRadius: BorderRadius.circular(8),
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

  const _MeasureTabStrip({
    required this.measureCount,
    required this.activeMeasure,
    required this.onSelect,
    required this.onAddMeasure,
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
  final VoidCallback onTap;

  const _MeasureTabButton({
    super.key,
    this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        child: icon != null ? Icon(icon, size: 20) : Text(label!),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final EventType selected;
  final ValueChanged<EventType> onSelect;

  const _TypeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: EventType.values.map((type) {
        final isSelected = type == selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(
            key: Key('type_${type.name}'),
            onPressed: () => onSelect(type),
            style: OutlinedButton.styleFrom(
              backgroundColor:
                  isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
            ),
            child: Text(_label(type)),
          ),
        );
      }).toList(),
    );
  }

  String _label(EventType type) {
    switch (type) {
      case EventType.rest:
        return 'Rest';
      case EventType.normal:
        return 'Normal';
      case EventType.accent:
        return 'Accent';
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  final String keyName;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _DurationButton({
    required this.keyName,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: Key(keyName),
      onPressed: enabled ? onTap : null,
      child: Text(label),
    );
  }
}
