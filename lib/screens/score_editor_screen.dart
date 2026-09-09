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

  /// Continuous position across the whole score, in sixteenth-note units.
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
          _activeMeasure = (units / RhythmGrid.unitsPerMeasure)
              .floor()
              .clamp(0, RhythmGrid.measuresCount - 1);
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

  Future<void> _togglePlay() async {
    if (_player.isPlaying) {
      await _player.stop();
      setState(() {});
      return;
    }
    _score = _score.copyWith(tempoBpm: _readTempo());
    setState(() {});
    await _player.play(_score);
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
    final measureStartUnits = _activeMeasure * RhythmGrid.unitsPerMeasure;
    final playheadInMeasure = _playheadUnits != null &&
            _playheadUnits! >= measureStartUnits &&
            _playheadUnits! < measureStartUnits + RhythmGrid.unitsPerMeasure
        ? _playheadUnits! - measureStartUnits
        : null;

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
                ],
              ),
              const SizedBox(height: 16),
              _MeasureTabStrip(
                activeMeasure: _activeMeasure,
                onSelect: (index) => setState(() => _activeMeasure = index),
              ),
              const SizedBox(height: 12),
              StaffNotationView(
                measure: measure,
                playheadUnits: playheadInMeasure,
                showCursor: !_player.isPlaying,
              ),
              const SizedBox(height: 4),
              Text('${measure.filledUnits}/${RhythmGrid.unitsPerMeasure} units filled'),
              const SizedBox(height: 12),
              _TypeSelector(
                selected: _selectedType,
                onSelect: (type) => setState(() => _selectedType = type),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
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

class _MeasureTabStrip extends StatelessWidget {
  final int activeMeasure;
  final ValueChanged<int> onSelect;

  const _MeasureTabStrip({required this.activeMeasure, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(RhythmGrid.measuresCount, (index) {
        final selected = index == activeMeasure;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: OutlinedButton(
              key: Key('measure_tab_$index'),
              onPressed: () => onSelect(index),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    selected ? Theme.of(context).colorScheme.primaryContainer : null,
                padding: EdgeInsets.zero,
              ),
              child: Text('${index + 1}'),
            ),
          ),
        );
      }),
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
