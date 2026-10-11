import 'package:flutter/material.dart';

/// What the player chose in [showSectionDialog]: a name and a range of the
/// mother track's measures (0-based, both included).
class SectionChoice {
  final String name;
  final int firstMeasure;
  final int lastMeasure;

  const SectionChoice({required this.name, required this.firstMeasure, required this.lastMeasure});
}

/// Asks for a section of a track [measureCount] measures long: its name,
/// and which measures it covers. Starts from [name] and the given range
/// (e.g. the section's current ones, when editing). Returns null if
/// cancelled.
Future<SectionChoice?> showSectionDialog(
  BuildContext context, {
  required String title,
  required int measureCount,
  required String name,
  int firstMeasure = 0,
  int? lastMeasure,
}) {
  return showDialog<SectionChoice>(
    context: context,
    builder: (context) => _SectionDialog(
      title: title,
      measureCount: measureCount,
      name: name,
      firstMeasure: firstMeasure.clamp(0, measureCount - 1),
      lastMeasure: (lastMeasure ?? measureCount - 1).clamp(0, measureCount - 1),
    ),
  );
}

class _SectionDialog extends StatefulWidget {
  final String title;
  final int measureCount;
  final String name;
  final int firstMeasure;
  final int lastMeasure;

  const _SectionDialog({
    required this.title,
    required this.measureCount,
    required this.name,
    required this.firstMeasure,
    required this.lastMeasure,
  });

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  late final _name = TextEditingController(text: widget.name);
  late int _first = widget.firstMeasure;
  late int _last = widget.lastMeasure < widget.firstMeasure ? widget.firstMeasure : widget.lastMeasure;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _measurePicker({
    required Key key,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    // A plain (controlled) dropdown: picking one end can move the other.
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: key,
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (var index = 0; index < widget.measureCount; index++)
              DropdownMenuItem(value: index, child: Text('Measure ${index + 1}')),
          ],
          onChanged: (index) {
            if (index != null) onChanged(index);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final measures = _last - _first + 1;
    return AlertDialog(
      key: const Key('section_dialog'),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('section_name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Fill, Bridge, Ending'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _measurePicker(
                    key: const Key('section_from'),
                    label: 'From',
                    value: _first,
                    // Moving the start past the end drags the end along.
                    onChanged: (index) => setState(() {
                      _first = index;
                      if (_last < index) _last = index;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _measurePicker(
                    key: const Key('section_to'),
                    label: 'To',
                    value: _last,
                    onChanged: (index) => setState(() {
                      _last = index;
                      if (_first > index) _first = index;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$measures ${measures == 1 ? 'measure' : 'measures'}. The section stays linked to '
              'the track: editing the track changes it too.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('section_save'),
          onPressed: () {
            final name = _name.text.trim();
            Navigator.of(context).pop(
              SectionChoice(
                name: name.isEmpty ? widget.name : name,
                firstMeasure: _first,
                lastMeasure: _last,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
