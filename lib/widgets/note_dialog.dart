import 'package:flutter/material.dart';

/// Asks for the player's note about a practice run, starting from
/// [initial]. Returns the new note (trimmed; may be empty to clear it), or
/// null if cancelled.
Future<String?> showRunNoteDialog(BuildContext context, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note about this run'),
      content: TextField(
        key: const Key('run_note_field'),
        controller: controller,
        autofocus: true,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'e.g. rushed the fill in measure 3',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('run_note_save'),
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
