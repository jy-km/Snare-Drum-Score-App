import 'dart:async';

import 'package:flutter/material.dart';

import '../models/rhythm_score.dart';
import '../services/rhythm_player.dart';
import '../services/score_storage.dart';

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
  PlaybackPosition? _playbackPosition;
  StreamSubscription<PlaybackPosition?>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _titleController = TextEditingController(text: _score.title);
    _tempoController = TextEditingController(text: _score.tempoBpm.toString());
    _positionSubscription = _player.positionStream.listen((position) {
      setState(() {
        _playbackPosition = position;
        if (position != null) _activeMeasure = position.measureIndex;
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

  void _cycleCell(int cellIndex) {
    setState(() {
      final measure = _score.measures[_activeMeasure];
      final updatedMeasure = measure.copyWithBeat(
        cellIndex,
        measure.beats[cellIndex].next,
      );
      _score = _score.copyWithMeasure(_activeMeasure, updatedMeasure);
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
    final highlightCell = _playbackPosition != null && _playbackPosition!.measureIndex == _activeMeasure
        ? _playbackPosition!.cellIndex
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Rhythm')),
      body: SafeArea(
        child: Padding(
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
              const SizedBox(height: 20),
              _MeasureTabStrip(
                activeMeasure: _activeMeasure,
                onSelect: (index) => setState(() => _activeMeasure = index),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _BeatGrid(
                  measure: measure,
                  highlightCell: highlightCell,
                  onCellTap: _cycleCell,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _togglePlay,
                    icon: Icon(_player.isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_player.isPlaying ? 'Stop' : 'Play'),
                  ),
                  ElevatedButton.icon(
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

class _BeatGrid extends StatelessWidget {
  final Measure measure;
  final int? highlightCell;
  final ValueChanged<int> onCellTap;

  const _BeatGrid({
    required this.measure,
    required this.highlightCell,
    required this.onCellTap,
  });

  static const double _labelWidth = 20;
  static const double _cellMargin = 4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCellWidth = (constraints.maxWidth - _labelWidth - 8) /
                RhythmGrid.subdivisionsPerBeat -
            _cellMargin * 2;
        final maxCellHeight =
            constraints.maxHeight / RhythmGrid.beatsPerMeasure - _cellMargin * 2;
        final cellSize = maxCellWidth < maxCellHeight ? maxCellWidth : maxCellHeight;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(RhythmGrid.beatsPerMeasure, (beatRow) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: _labelWidth, child: Text('${beatRow + 1}')),
                const SizedBox(width: 8),
                ...List.generate(RhythmGrid.subdivisionsPerBeat, (sub) {
                  final cellIndex = beatRow * RhythmGrid.subdivisionsPerBeat + sub;
                  return _buildCell(context, cellIndex, cellSize);
                }),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, int cellIndex, double size) {
    final beat = measure.beats[cellIndex];
    final isHighlighted = highlightCell == cellIndex;

    return Padding(
      padding: const EdgeInsets.all(_cellMargin),
      child: GestureDetector(
        key: Key('beat_cell_$cellIndex'),
        onTap: () => onCellTap(cellIndex),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _cellColor(context, beat.state),
            border: Border.all(
              color: isHighlighted ? Colors.orange : Colors.grey,
              width: isHighlighted ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: beat.state == BeatState.accent
              ? const Center(
                  child: Text('>', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : null,
        ),
      ),
    );
  }

  Color? _cellColor(BuildContext context, BeatState state) {
    final primary = Theme.of(context).colorScheme.primary;
    switch (state) {
      case BeatState.rest:
        return null;
      case BeatState.normal:
        return primary.withValues(alpha: 0.5);
      case BeatState.accent:
        return primary;
    }
  }
}
