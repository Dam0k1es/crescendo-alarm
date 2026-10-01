// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

part of 'screen_schedule.dart';

/// One device-calendar event as the app sees it ([eventToMeeting]), drawn by
/// the Schedule tab ([meetingToCalendarEvent]) and read by scheduling-v2.
/// [from] and [to] are absolute instants: the `tz.TZDateTime`s
/// `device_calendar` returns, in the event's own zone.
class Meeting {
  Meeting({
    required this.from,
    required this.to,
    this.background = Colors.green,
    this.isAllDay = false,
    this.eventName = '',
    required this.startTimeZone,
    required this.endTimeZone,
    this.description = '',
    this.ids = const [],
  });

  String eventName;
  DateTime from;
  DateTime to;
  Color background;
  bool isAllDay;
  String startTimeZone;
  String endTimeZone;
  String description;
  List<String> ids;

  @override
  bool operator ==(Object other) {
    if (other is Meeting) {
      return from == other.from &&
          to == other.to &&
          background == other.background &&
          isAllDay == other.isAllDay &&
          eventName == other.eventName &&
          startTimeZone == other.startTimeZone &&
          endTimeZone == other.endTimeZone &&
          description == other.description &&
          listEquals(ids, other.ids);
    } else {
      return false;
    }
  }

  // Hashes exactly the fields `==` above compares, so equal meetings hash
  // equally; `Object.hashAll` because `==` compares [ids] by content
  // (`listEquals`), not by identity.
  @override
  int get hashCode => Object.hash(
        from,
        to,
        background,
        isAllDay,
        eventName,
        startTimeZone,
        endTimeZone,
        description,
        Object.hashAll(ids),
      );
}

/// Maps one [Meeting] onto the event object calendar_view draws
/// (docs/TODO.md T-05).
///
/// **The frame conversion lives here, and getting it right is the whole job.**
/// Syncfusion's `CalendarDataSource` took a `startTimeZone` per appointment;
/// `calendar_view` has no timezone concept at all and draws the raw fields of
/// whatever `DateTime` it is handed. `device_calendar` hands out
/// `tz.TZDateTime` in the *event's own* zone, so something has to convert.
///
/// It must NOT be `toLocal()`. On a `TZDateTime` that converts to `tz.local`,
/// and `tz.local` stays `Etc/UTC` unless somebody calls `tz.setLocalLocation` -
/// which this app never does (`tzdata.initializeTimeZones()` in main.dart only
/// loads the database). `toLocal()` on these values is therefore `toUtc()` in
/// disguise, and the first version of this function used it: a 09:00 Berlin
/// appointment was drawn at 07:00 in summer. `DateTime.fromMillisecondsSinceEpoch`
/// is the conversion that actually asks the *device* - same instant, read in
/// the zone the user's clock shows. (On a plain `DateTime`, `toLocal()` does
/// ask the device. Same method name, different runtime type, different frame -
/// the T-61/T-83 trap one level deeper.)
///
/// **All-day entries are the exception and must not take that path.**
/// `device_calendar` deliberately normalises an Android all-day event to
/// midnight UTC to preserve its calendar date (see its `Event.fromJson`), so
/// their date has to be read in UTC too. Converting them to device time would
/// move every all-day event one day earlier for any device west of UTC. They
/// also carry no start/end time: calendar_view reads that as a full-day event,
/// while 00:00-00:00 would be drawn as a sliver at the top of the time grid.
///
/// [ignored] (docs/TODO.md T-149): drawn grey regardless of the
/// event's real colour when the user has chosen to leave this appointment
/// out of scheduling - `DefaultEventTile` (calendar_view) draws a
/// `CalendarEventData`'s `color` as its whole background, so this is the
/// entire "grayed out" half of the requirement. The X-overlay half needs an
/// actual tile builder and lives in screen_schedule.dart instead.
CalendarEventData<Meeting> meetingToCalendarEvent(
  Meeting meeting, {
  bool ignored = false,
}) {
  final color = ignored ? Colors.grey : meeting.background;
  if (meeting.isAllDay) {
    final fromDay = meeting.from.toUtc();
    final toDay = meeting.to.toUtc();
    return CalendarEventData<Meeting>(
      title: meeting.eventName,
      description: meeting.description,
      color: color,
      event: meeting,
      date: DateTime(fromDay.year, fromDay.month, fromDay.day),
      endDate: DateTime(toDay.year, toDay.month, toDay.day),
    );
  }

  final from =
      DateTime.fromMillisecondsSinceEpoch(meeting.from.millisecondsSinceEpoch);
  final to =
      DateTime.fromMillisecondsSinceEpoch(meeting.to.millisecondsSinceEpoch);

  return CalendarEventData<Meeting>(
    title: meeting.eventName,
    description: meeting.description,
    color: color,
    event: meeting,
    date: DateTime(from.year, from.month, from.day),
    endDate: DateTime(to.year, to.month, to.day),
    startTime: from,
    endTime: to,
  );
}

// For future development
// Event meetingToEvent(Meeting meeting) {
//   return Event(
//     calendars.first.id,
//     title: meeting.eventName,
//     description: meeting.description,
//     start:
//         tz.TZDateTime.from(meeting.from, tz.getLocation(meeting.startTimeZone)),
//     end: tz.TZDateTime.from(meeting.to, tz.getLocation(meeting.endTimeZone)),
//     allDay: meeting.isAllDay,
//   );
// }

Meeting eventToMeeting(Event event, Color selectedColor, String startTimeZone,
    String endTimeZone) {
  return Meeting(
    from: event.start!,
    to: event.end!,
    eventName: event.title ?? '(No title)',
    description: event.description ?? '',
    isAllDay: event.allDay ?? false,
    background: selectedColor,
    startTimeZone: startTimeZone,
    ids: [event.eventId!],
    endTimeZone: endTimeZone,
  );
}
