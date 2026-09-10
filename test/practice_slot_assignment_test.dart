import 'package:flutter_test/flutter_test.dart';

import 'package:snare_drum_score_app/services/practice_slot_assignment.dart';

void main() {
  test('slotForMeasure rotates A,B,C', () {
    expect(slotForMeasure(0), PracticeSlot.a);
    expect(slotForMeasure(1), PracticeSlot.b);
    expect(slotForMeasure(2), PracticeSlot.c);
    expect(slotForMeasure(3), PracticeSlot.a);
    expect(slotForMeasure(7), PracticeSlot.b);
  });

  test('reset assigns measures 1-3 to slots A-C with no current measure', () {
    final slots = PracticeSlotAssignment();
    expect(slots.content[PracticeSlot.a], 0);
    expect(slots.content[PracticeSlot.b], 1);
    expect(slots.content[PracticeSlot.c], 2);
    expect(slots.currentMeasureIndex, isNull);
  });

  test('advancing to the first measure does not refresh any slot', () {
    final slots = PracticeSlotAssignment();
    slots.advanceTo(0);
    expect(slots.currentMeasureIndex, 0);
    expect(slots.content[PracticeSlot.a], 0);
    expect(slots.content[PracticeSlot.b], 1);
    expect(slots.content[PracticeSlot.c], 2);
  });

  test('full 8-measure transition table refreshes 2 measures ahead, blanking at the tail', () {
    final slots = PracticeSlotAssignment();
    slots.advanceTo(0); // measure 1 playing

    slots.advanceTo(1); // measure 2 playing -> slot A refreshed to measure 4
    expect(slots.content[PracticeSlot.a], 3);
    expect(slots.content[PracticeSlot.b], 1);
    expect(slots.content[PracticeSlot.c], 2);

    slots.advanceTo(2); // measure 3 playing -> slot B refreshed to measure 5
    expect(slots.content[PracticeSlot.a], 3);
    expect(slots.content[PracticeSlot.b], 4);
    expect(slots.content[PracticeSlot.c], 2);

    slots.advanceTo(3); // measure 4 playing -> slot C refreshed to measure 6
    expect(slots.content[PracticeSlot.a], 3);
    expect(slots.content[PracticeSlot.b], 4);
    expect(slots.content[PracticeSlot.c], 5);

    slots.advanceTo(4); // measure 5 playing -> slot A refreshed to measure 7
    expect(slots.content[PracticeSlot.a], 6);
    expect(slots.content[PracticeSlot.b], 4);
    expect(slots.content[PracticeSlot.c], 5);

    slots.advanceTo(5); // measure 6 playing -> slot B refreshed to measure 8
    expect(slots.content[PracticeSlot.a], 6);
    expect(slots.content[PracticeSlot.b], 7);
    expect(slots.content[PracticeSlot.c], 5);

    slots.advanceTo(6); // measure 7 playing -> slot C would refresh to measure 9: blank
    expect(slots.content[PracticeSlot.a], 6);
    expect(slots.content[PracticeSlot.b], 7);
    expect(slots.content[PracticeSlot.c], isNull);

    slots.advanceTo(7); // measure 8 playing -> slot A would refresh to measure 10: blank
    expect(slots.content[PracticeSlot.a], isNull);
    expect(slots.content[PracticeSlot.b], 7);
    expect(slots.content[PracticeSlot.c], isNull);
  });

  test('reset clears back to the initial assignment', () {
    final slots = PracticeSlotAssignment();
    slots.advanceTo(0);
    slots.advanceTo(1);
    slots.reset();
    expect(slots.content[PracticeSlot.a], 0);
    expect(slots.content[PracticeSlot.b], 1);
    expect(slots.content[PracticeSlot.c], 2);
    expect(slots.currentMeasureIndex, isNull);
  });
}
