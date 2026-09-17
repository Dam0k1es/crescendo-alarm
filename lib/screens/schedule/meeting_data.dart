part of 'screen_schedule.dart';

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

  @override
  int get hashCode {
    return jsonEncode(this).hashCode;
  }

// TODO: verify correct de/serialization of meeting objects
// @override
// String toJson() {
//   return jsonEncode({
//     'from': from,
//     'to': to,
//     'background': background,
//     'isAllDay': isAllDay,
//     'eventName': eventName,
//     'startTimeZone': startTimeZone,
//     'endTimeZone': endTimeZone,
//     'description': description,
//     'ids': ids,
//   });
// }
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
/// the zone the user's clock shows. (`alarmPlatformTime` in lib/utils/utils.dart
/// uses `.toLocal()` and is correct, because its receiver is a plain UTC
/// `DateTime`. Same method name, different runtime type, different frame - the
/// T-61/T-83 trap one level deeper.)
///
/// **All-day entries are the exception and must not take that path.**
/// `device_calendar` deliberately normalises an Android all-day event to
/// midnight UTC to preserve its calendar date (see its `Event.fromJson`), so
/// their date has to be read in UTC too. Converting them to device time would
/// move every all-day event one day earlier for any device west of UTC. They
/// also carry no start/end time: calendar_view reads that as a full-day event,
/// while 00:00-00:00 would be drawn as a sliver at the top of the time grid.
CalendarEventData<Meeting> meetingToCalendarEvent(Meeting meeting) {
  if (meeting.isAllDay) {
    final fromDay = meeting.from.toUtc();
    final toDay = meeting.to.toUtc();
    return CalendarEventData<Meeting>(
      title: meeting.eventName,
      description: meeting.description,
      color: meeting.background,
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
    color: meeting.background,
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
