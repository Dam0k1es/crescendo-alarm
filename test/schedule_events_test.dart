import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

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

    test('a timed appointment is rendered in the DEVICE zone', () {
      // An independent review proved the previous version of this test was a
      // tautology: it compared the result against `from.toLocal()`, which is
      // the implementation's own expression, so it asserted x == x. It passed
      // in every timezone while the screen drew every appointment at the wrong
      // hour.
      //
      // The trap underneath: `meeting.from` is a `tz.TZDateTime` from
      // device_calendar, and `TZDateTime.toLocal()` converts to `tz.local` -
      // which stays `Etc/UTC` unless somebody calls `tz.setLocalLocation`, and
      // this app never does. So `.toLocal()` was `.toUtc()` in disguise: a
      // 09:00 Berlin appointment was drawn at 07:00 in summer.
      //
      // The oracle here is therefore a property that holds in EVERY zone and
      // is false for the broken version: the value handed to calendar_view
      // must be an ordinary local DateTime, not a UTC-tagged one.
      final from = tz.TZDateTime(berlin, 2026, 7, 10, 9, 0); // CEST, UTC+2
      final to = tz.TZDateTime(berlin, 2026, 7, 10, 10, 30);

      final event = meetingToCalendarEvent(_meeting(from: from, to: to));

      expect(event.startTime!.isUtc, isFalse,
          reason: 'calendar_view draws raw fields; a UTC-tagged value draws '
              'the UTC hour');
      expect(
          event.startTime!.millisecondsSinceEpoch, from.millisecondsSinceEpoch,
          reason: 'same instant - only the frame it is read in may change');
      expect(event.endTime!.millisecondsSinceEpoch, to.millisecondsSinceEpoch);

      // And the fields really are the device reading of that instant. Derived
      // through the platform's own conversion rather than through the
      // implementation's expression.
      final deviceReading =
          DateTime.fromMillisecondsSinceEpoch(from.millisecondsSinceEpoch);
      expect([event.startTime!.hour, event.startTime!.minute],
          [deviceReading.hour, deviceReading.minute]);
      expect(event.date,
          DateTime(deviceReading.year, deviceReading.month, deviceReading.day));
    });

    test('outside UTC the rendered hour is not the UTC hour', () {
      // The concrete regression, stated as the user would see it. Meaningful
      // only where the device is not at UTC+0 - which is why CI runs this
      // suite over six timezones, and why the dev machine alone could never
      // have caught the defect above.
      final from = tz.TZDateTime(berlin, 2026, 7, 10, 9, 0);
      final event = meetingToCalendarEvent(
          _meeting(from: from, to: from.add(const Duration(hours: 1))));

      final deviceOffset =
          DateTime.fromMillisecondsSinceEpoch(from.millisecondsSinceEpoch)
              .timeZoneOffset;
      if (deviceOffset == Duration.zero) {
        // At UTC+0 the two readings coincide; nothing to assert.
        return;
      }
      expect(event.startTime!.hour, isNot(from.toUtc().hour),
          reason: 'the appointment must be drawn at the wall-clock time the '
              'user reads on this device, not at the UTC hour');
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

    test('an all-day entry keeps its calendar date west of UTC', () {
      // device_calendar normalises an Android all-day event to midnight UTC so
      // that its DATE survives. Reading that through the device zone would
      // move it to the previous evening for any negative offset - the whole
      // entry would jump a day back for users west of UTC. CI's St John's and
      // Chatham legs are where this bites.
      final event = meetingToCalendarEvent(_meeting(
        from: tz.TZDateTime.utc(2026, 7, 10),
        to: tz.TZDateTime.utc(2026, 7, 11),
        isAllDay: true,
      ));

      expect(event.date, DateTime(2026, 7, 10),
          reason: 'the date the calendar app showed, in every device zone');
      expect(event.isFullDayEvent, isTrue);
    });

    test('a multi-day appointment spans to its last day', () {
      final event = meetingToCalendarEvent(_meeting(
        from: tz.TZDateTime(berlin, 2026, 3, 10, 9, 0),
        to: tz.TZDateTime(berlin, 2026, 3, 12, 17, 0),
      ));

      // The last day AS THE DEVICE READS IT. This expectation has now been
      // wrong twice, in two different ways, which is a fair measure of how
      // slippery the frames are here: first it was built from midnight in
      // Berlin (00:00 Berlin is the previous day in UTC), then it used
      // `.toLocal()`, which on a TZDateTime means `tz.local` - still UTC - and
      // so failed in Chatham at UTC+12:45, where a 17:00 Berlin end really is
      // the following day locally. The device reading is the one calendar_view
      // draws, so it is the one to assert.
      final localTo = DateTime.fromMillisecondsSinceEpoch(
          tz.TZDateTime(berlin, 2026, 3, 12, 17, 0).millisecondsSinceEpoch);
      expect(event.endDate, DateTime(localTo.year, localTo.month, localTo.day),
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
