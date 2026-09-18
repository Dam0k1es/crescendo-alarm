import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// New feature (user request): an ignored event must be shown "grayed out"
// on the calendar. calendar_view's DefaultEventTile draws a
// CalendarEventData's own `color` as its background - so overriding that to
// grey when [ignored] is true is the entire "grayed out" half of the
// requirement, with no custom tile rendering needed at all. The X-overlay
// half lives in the widget layer (screen_schedule_test.dart), since it needs
// a real tile builder to draw on top of.

Meeting _meeting({bool isAllDay = false}) => Meeting(
      from: DateTime.utc(2026, 3, 10, 8, 0),
      to: DateTime.utc(2026, 3, 10, 9, 0),
      isAllDay: isAllDay,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
      background: Colors.green,
      ids: const ['evt-1'],
    );

void main() {
  test('a non-ignored event keeps the calendar-assigned colour', () {
    final event = meetingToCalendarEvent(_meeting());
    expect(event.color, Colors.green);
  });

  test('an ignored event is drawn grey regardless of its real colour', () {
    final event = meetingToCalendarEvent(_meeting(), ignored: true);
    expect(event.color, Colors.grey);
  });

  test('an ignored all-day event is also drawn grey', () {
    final event =
        meetingToCalendarEvent(_meeting(isAllDay: true), ignored: true);
    expect(event.color, Colors.grey);
  });
}
