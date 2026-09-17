import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-05: the Schedule screen moved from Syncfusion's SfCalendar to
// calendar_view. `Meeting` stays exactly as it is - the scheduling engine and
// most of the test suite depend on it - so the migration is a mapping, and
// this file tests that mapping.
//
// The mapping is where the migration can go wrong quietly, and in a way this
// project has been bitten by three times (T-61, T-76, T-83): SfCalendar took a
// `startTimeZone` per appointment and did the conversion itself.
// `calendar_view` has no timezone concept at all - it renders the fields of
// whatever DateTime it is handed. So the conversion has to happen in the
// mapping, or every appointment is drawn at the wrong hour.
//
// Fixtures are `tz.TZDateTime`, never `DateTime.utc`: the dev VM runs at UTC+0,
// where a frame error is invisible by construction.

Meeting _meeting({
  required DateTime from,
  required DateTime to,
  bool isAllDay = false,
  String name = 'Standup',
}) =>
    Meeting(
      from: from,
      to: to,
      eventName: name,
      description: 'notes',
      isAllDay: isAllDay,
      background: Colors.teal,
      startTimeZone: 'Europe/Berlin',
      endTimeZone: 'Europe/Berlin',
      ids: const ['e1'],
    );

void main() {
  late tz.Location berlin;

  setUpAll(() {
    tzdata.initializeTimeZones();
    berlin = tz.getLocation('Europe/Berlin');
  });

  group('Meeting -> CalendarEventData', () {
    test('title, description and colour are carried over', () {
      final event = meetingToCalendarEvent(_meeting(
        from: tz.TZDateTime(berlin, 2026, 3, 10, 9, 0),
        to: tz.TZDateTime(berlin, 2026, 3, 10, 10, 0),
      ));

      expect(event.title, 'Standup');
      expect(event.description, 'notes');
      expect(event.color, Colors.teal);
      expect(event.event?.ids, const ['e1'],
          reason: 'the Meeting itself has to travel with the event - it is '
              'what a tap would need');
    });

    test('a timed appointment keeps its instant and is read locally', () {
      // 09:00 in Berlin is 08:00 UTC in March (CET). What must NOT happen is
      // the T-61 mistake: taking the digits of one frame and declaring them
      // the other.
      final from = tz.TZDateTime(berlin, 2026, 3, 10, 9, 0);
      final to = tz.TZDateTime(berlin, 2026, 3, 10, 10, 30);

      final event = meetingToCalendarEvent(_meeting(from: from, to: to));

      expect(event.startTime!.isAtSameMomentAs(from), isTrue,
          reason: 'same instant, whatever the device zone is');
      expect(event.endTime!.isAtSameMomentAs(to), isTrue);

      // The fields calendar_view will DRAW must be the device-local reading.
      // Deriving the expectation from `from.toLocal()` rather than writing
      // "09:00" keeps this true in every leg of the timezone matrix, and it
      // still catches the mutation that matters: without `.toLocal()` the
      // event keeps Berlin's 09:00 while the device here reads 08:00.
      final localFrom = from.toLocal();
      expect([event.startTime!.hour, event.startTime!.minute],
          [localFrom.hour, localFrom.minute],
          reason: 'calendar_view draws raw fields - a value left in another '
              'frame is drawn at the wrong hour');
      expect(event.date,
          DateTime(localFrom.year, localFrom.month, localFrom.day));
    });

    test('an all-day appointment becomes a full-day event', () {
      final event = meetingToCalendarEvent(_meeting(
        from: tz.TZDateTime(berlin, 2026, 3, 10),
        to: tz.TZDateTime(berlin, 2026, 3, 11),
        isAllDay: true,
      ));

      expect(event.isFullDayEvent, isTrue,
          reason: 'an all-day entry must not be drawn as a 00:00-00:00 sliver '
              'in the time grid');
    });

    test('a multi-day appointment spans to its last day', () {
      final event = meetingToCalendarEvent(_meeting(
        from: tz.TZDateTime(berlin, 2026, 3, 10, 9, 0),
        to: tz.TZDateTime(berlin, 2026, 3, 12, 17, 0),
      ));

      // Derived from the END of the appointment as the device reads it. The
      // first version of this expectation built midnight in Berlin instead and
      // was simply wrong: 00:00 Berlin is 23:00 the previous day in UTC, so it
      // demanded the 11th for an appointment ending on the 12th. The code was
      // right and the hand-written fixture was not - re-derived rather than
      // pasted from the failure message.
      final localTo = tz.TZDateTime(berlin, 2026, 3, 12, 17, 0).toLocal();
      expect(event.endDate,
          DateTime(localTo.year, localTo.month, localTo.day),
          reason: 'otherwise a conference disappears after its first day');
    });

    test('a list of meetings maps one to one', () {
      // Counter-test against a mapping that silently drops entries (all-day
      // ones, say) - the calendar would then just be missing appointments.
      final meetings = [
        _meeting(
          from: tz.TZDateTime(berlin, 2026, 3, 10, 9, 0),
          to: tz.TZDateTime(berlin, 2026, 3, 10, 10, 0),
          name: 'a',
        ),
        _meeting(
          from: tz.TZDateTime(berlin, 2026, 3, 11),
          to: tz.TZDateTime(berlin, 2026, 3, 12),
          isAllDay: true,
          name: 'b',
        ),
      ];

      final events = meetings.map(meetingToCalendarEvent).toList();

      expect(events.map((e) => e.title), ['a', 'b']);
    });
  });
}
