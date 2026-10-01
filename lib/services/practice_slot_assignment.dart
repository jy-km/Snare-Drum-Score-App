import '../models/rhythm_score.dart';

/// One of the 3 fixed on-screen positions in the practice screen's
/// ring-buffer measure display.
enum PracticeSlot { a, b, c }

/// Which slot a given (0-based) measure index belongs to. Slot roles rotate
/// through measures rather than being pinned to a fixed measure range, so
/// this is used both to find "the currently active slot" and "the slot to
/// refresh next."
PracticeSlot slotForMeasure(int measureIndex) => PracticeSlot.values[measureIndex % 3];

/// Tracks which measure each of the 3 fixed practice-screen slots currently
/// displays, refreshing a slot 2 measures ahead of the one it just finished
/// showing -- so a measure is visible for 2 full measures before it's due to
/// be played, and each slot's *content* rotates while its *screen position*
/// stays fixed.
class PracticeSlotAssignment {
  /// Total number of measures in the sequence being displayed. Defaults to a
  /// plain score ([RhythmGrid.defaultMeasuresCount]); callers prepending
  /// extra measures (e.g. a count-in) pass the larger total so blanking at
  /// the tail still lands on the true last measure.
  final int measuresCount;

  final Map<PracticeSlot, int?> content = {
    PracticeSlot.a: 0,
    PracticeSlot.b: 1,
    PracticeSlot.c: 2,
  };

  int? currentMeasureIndex;

  PracticeSlotAssignment({this.measuresCount = RhythmGrid.defaultMeasuresCount});

  void reset() {
    content[PracticeSlot.a] = 0;
    content[PracticeSlot.b] = 1;
    content[PracticeSlot.c] = 2;
    currentMeasureIndex = null;
  }

  /// Advances the current measure to [newMeasureIndex], refreshing the slot
  /// whose measure just finished. Only moves forward -- this is a
  /// single-playthrough ring buffer, not a general seek.
  void advanceTo(int newMeasureIndex) {
    if (currentMeasureIndex != null && newMeasureIndex > currentMeasureIndex!) {
      final refreshed = slotForMeasure(newMeasureIndex - 1);
      final candidate = newMeasureIndex + 2;
      content[refreshed] = candidate < measuresCount ? candidate : null;
    }
    currentMeasureIndex = newMeasureIndex;
  }
}
