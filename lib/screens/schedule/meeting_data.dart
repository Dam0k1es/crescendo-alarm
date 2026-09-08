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

class DataSource extends CalendarDataSource {
  DataSource(List<Meeting> source) {
    appointments = source;
  }

  @override
  bool isAllDay(int index) => appointments![index].isAllDay;

  @override
  String getSubject(int index) => appointments![index].eventName;

  @override
  String getStartTimeZone(int index) => appointments![index].startTimeZone;

  @override
  String getNotes(int index) => appointments![index].description;

  @override
  String getEndTimeZone(int index) => appointments![index].endTimeZone;

  @override
  Color getColor(int index) => appointments![index].background;

  @override
  DateTime getStartTime(int index) => appointments![index].from;

  @override
  DateTime getEndTime(int index) => appointments![index].to;
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
