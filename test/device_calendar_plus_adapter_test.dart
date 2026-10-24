import 'dart:ui' show Color;

import 'package:device_calendar_plus/device_calendar_plus.dart' as plus;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// The calendar boundary moved from `device_calendar` to `device_calendar_plus`
// (docs/TODO.md T-244). The two plugins hand out different frames: the old one
// returned a `TZDateTime` in the event's own zone and normalised an all-day
// event to midnight UTC; the new one returns plain device-local `DateTime`s and
// reads an all-day event as LOCAL midnight of its calendar date. `Meeting`
// keeps its old convention (timed: an instant; all-day: UTC-tagged midnight of
// the date), so everything downstream - the planner, the Schedule tab, the
// ignored-event ids - is unchanged, and this file pins the adapter that keeps
// that true. Fixtures are device-local `DateTime`s: this suite runs in ten
// zones, and a frame error is only visible away from UTC+0.

plus.Event _event({
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String title = 'Standup',
  String eventId = 'e1',
  String? instanceId,
  plus.EventStatus status = plus.EventStatus.confirmed,
  bool recurring = false,
}) =>
    plus.Event(
      eventId: eventId,
      instanceId: instanceId ?? eventId,
      calendarId: 'cal',
      title: title,
      startDate: start,
      endDate: end,
      isAllDay: allDay,
      availability: plus.EventAvailability.busy,
      status: status,
      isRecurring: recurring,
    );

void main() {
  const color = Color(0xFF123456);

  group('a timed event', () {
    test('keeps its instants whatever zone the device is in', () {
      final start = DateTime(2026, 7, 10, 9, 0);
      final end = DateTime(2026, 7, 10, 10, 30);

      final m = eventToMeeting(_event(start: start, end: end), color, '', '');

      expect(m.from.millisecondsSinceEpoch, start.millisecondsSinceEpoch);
      expect(m.to.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
      expect(m.isAllDay, isFalse);
    });

    test('carries title, colour and the event id (the ignored-event key)', () {
      final m = eventToMeeting(
          _event(
              start: DateTime(2026, 7, 10, 9),
              end: DateTime(2026, 7, 10, 10),
              eventId: 'series-7',
              instanceId: 'series-7@1783670400000',
              recurring: true),
          color,
          '',
          '');

      expect(m.eventName, 'Standup');
      expect(m.background, color);
      expect(m.ids, const ['series-7'],
          reason: 'persisted ignored ids are event ids; every occurrence of a '
              'series shares one, exactly as with device_calendar');
    });

    test('an empty title reads as "(No title)"', () {
      final m = eventToMeeting(
          _event(
              start: DateTime(2026, 7, 10, 9),
              end: DateTime(2026, 7, 10, 10),
              title: ''),
          color,
          '',
          '');
      expect(m.eventName, '(No title)');
    });
  });

  group('an all-day event', () {
    test('is read as UTC-tagged midnight of its calendar date', () {
      // The plugin reports local midnight of the date.
      final m = eventToMeeting(
          _event(
              start: DateTime(2026, 7, 10),
              end: DateTime(2026, 7, 11),
              allDay: true),
          color,
          '',
          '');

      expect(m.isAllDay, isTrue);
      expect(m.from, DateTime.utc(2026, 7, 10));
      expect(m.to, DateTime.utc(2026, 7, 11));
      expect(m.from.isUtc, isTrue);
    });

    test('keeps its date across a month boundary and a multi-day span', () {
      final m = eventToMeeting(
          _event(
              start: DateTime(2026, 7, 31),
              end: DateTime(2026, 8, 3),
              allDay: true),
          color,
          '',
          '');
      expect(m.from, DateTime.utc(2026, 7, 31));
      expect(m.to, DateTime.utc(2026, 8, 3));
    });

    test('renders as a full-day entry on the right date in every zone', () {
      final m = eventToMeeting(
          _event(
              start: DateTime(2026, 7, 10),
              end: DateTime(2026, 7, 11),
              allDay: true),
          color,
          '',
          '');
      final shown = meetingToCalendarEvent(m);
      expect(shown.isFullDayEvent, isTrue);
      expect(shown.date, DateTime(2026, 7, 10));
    });
  });

  group('eventsToMeetings', () {
    test('drops a cancelled occurrence and keeps the others', () {
      final events = [
        _event(
            start: DateTime(2026, 7, 10, 9),
            end: DateTime(2026, 7, 10, 10),
            eventId: 'keep'),
        _event(
            start: DateTime(2026, 7, 11, 9),
            end: DateTime(2026, 7, 11, 10),
            eventId: 'gone',
            status: plus.EventStatus.canceled),
        _event(
            start: DateTime(2026, 7, 12, 9),
            end: DateTime(2026, 7, 12, 10),
            eventId: 'maybe',
            status: plus.EventStatus.tentative),
        _event(
            start: DateTime(2026, 7, 13, 9),
            end: DateTime(2026, 7, 13, 10),
            eventId: 'plain',
            status: plus.EventStatus.none),
      ];

      final ids = eventsToMeetings(events, color).map((m) => m.ids.single);

      expect(ids, ['keep', 'maybe', 'plain'],
          reason: 'a cancelled appointment must not wake anyone early; '
              'tentative and status-less ones count as before');
    });

    test('an empty list maps to an empty list', () {
      expect(eventsToMeetings(const [], color), isEmpty);
    });
  });
}
