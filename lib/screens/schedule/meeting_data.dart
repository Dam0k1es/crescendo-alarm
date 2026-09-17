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
/// **The timezone conversion lives here, and it has to.** Syncfusion's
/// `CalendarDataSource` took a `startTimeZone` per appointment and converted
/// internally; `calendar_view` has no timezone concept at all and renders the
/// fields of whatever `DateTime` it is given. So a value arriving in another
/// frame - `device_calendar` hands out `TZDateTime` in the event's own zone -
/// must be read as DEVICE-LOCAL wall clock before it goes in, or every
/// appointment is drawn at the wrong hour. That is exactly the mistake class of
/// docs/TODO.md T-61/T-83, one layer further out.
///
/// An all-day entry deliberately carries no start/end time: calendar_view reads
/// that as a full-day event, while 00:00-00:00 would be drawn as a sliver at
/// the top of the time grid.
CalendarEventData<Meeting> meetingToCalendarEvent(Meeting meeting) {
  final from = meeting.from.toLocal();
  final to = meeting.to.toLocal();

  return CalendarEventData<Meeting>(
    title: meeting.eventName,
    description: meeting.description,
    color: meeting.background,
    event: meeting,
    date: DateTime(from.year, from.month, from.day),
    endDate: DateTime(to.year, to.month, to.day),
    startTime: meeting.isAllDay ? null : from,
    endTime: meeting.isAllDay ? null : to,
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
