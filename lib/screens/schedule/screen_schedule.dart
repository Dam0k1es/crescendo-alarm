import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

// Dependencies of calendar.dart and appointment_editor.dart
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/utils.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

part 'appointment_editor.dart';

part 'calendar.dart';

part 'color_picker.dart';

part 'meeting_data.dart';

// Define variables to hold the selected color, time zone, ...
int _selectedColorIndex = 0;
String _subject = '';
String _notes = '';
late bool _isAllDay;
DataSource _events = DataSource([]);
late DateTime _startDate;
late TimeOfDay _startTime;
late DateTime _endDate;
late TimeOfDay _endTime;
Meeting? _selectedAppointment;
late CalendarController _calendarController;
late AppState appState;

// Define the screen schedule widget.
class ScreenSchedule extends StatefulWidget {
  const ScreenSchedule({super.key});

  @override
  State<ScreenSchedule> createState() => _ScreenScheduleState();
}

// Define the screen schedule state.
class _ScreenScheduleState extends State<ScreenSchedule>
    with SingleTickerProviderStateMixin {
  // Initialize the screen schedule state.
  @override
  void initState() {
    debugPrint("=====initState");
    super.initState();
    _subject = '';
    _notes = '';
    _selectedColorIndex = 0;
    _selectedAppointment = null;
    _calendarController = CalendarController();
    appState = Provider.of<AppState>(context, listen: false);
    // _events = DataSource([
    //   Meeting(
    //     from: DateTime.now().subtract(const Duration(hours: 1)),
    //     to: DateTime.now(),
    //     eventName: 'Example Appointment 1',
    //     background: Colors.blue,
    //     ids: ["1"],
    //   ),
    //   Meeting(
    //     from: DateTime.now().subtract(const Duration(hours: 2)),
    //     to: DateTime.now().subtract(const Duration(hours: 1)),
    //     eventName: 'Example Appointment 2',
    //     background: Colors.green,
    //     ids: ["2"],
    //   ),
    // ]);
    _events = DataSource([]);
    // TODO test this
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   loadCalendarData(appState, const Duration(days: 7));
    // });
    setVisibleDate(appState.visibleDate);
  }

  // Update the visible date of the calendar
  void setVisibleDate(DateTime date) {
    setState(() {
      _calendarController.displayDate = date;
    });
    debugPrint("=====setVisibleDate: Moved the calendar view to $date");
  }

  // Define the screen schedule widget
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        // Define the app bar.
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Theme.of(context).colorScheme.surface,
          title: const Text(
            'Schedule',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Define the body of the screen.
        body: SfCalendar(
            controller: _calendarController,
            timeZone: appState.currentTimeZone,
            firstDayOfWeek: 1,
            timeSlotViewSettings: const TimeSlotViewSettings(
                timeFormat: 'HH:mm', startHour: 0, endHour: 24),
            backgroundColor: Theme.of(context).colorScheme.surface,
            headerStyle: CalendarHeaderStyle(
                backgroundColor: Theme.of(context).colorScheme.surface),
            viewHeaderStyle: ViewHeaderStyle(
                backgroundColor: Theme.of(context).colorScheme.surface),
            view: CalendarView.week,
            allowedViews: const <CalendarView>[
              CalendarView.day,
              CalendarView.week,
              CalendarView.workWeek,
              CalendarView.month
            ],
            showTodayButton: true,
            showNavigationArrow: true,
            todayHighlightColor: context.watch<AppState>().accentColor,
            selectionDecoration: BoxDecoration(
              color:
                  context.watch<AppState>().accentColor.withValues(alpha: 0.5),
              shape: BoxShape.rectangle,
            ),
            // appointmentTextStyle: TextStyle(
            //   color: context.watch<AppState>().accentColor,
            // ),
            showDatePickerButton: true,
            dataSource: _events,
            // onTap: onCalendarTapped,
            onViewChanged: (ViewChangedDetails details) {
              // use addPostFrameCallback to ensure
              // that the frame is called after it has been rendered
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onCalendarViewChanged(details);
              });
            }));
  }

  // Update the content of the calendar after the view has changed (initial or after user interaction)
  void onCalendarViewChanged(ViewChangedDetails viewChangedDetails) async {
    try {
      debugPrint(
          "=====onCalendarViewChanged: Visible date is ${viewChangedDetails.visibleDates.first} (Weekday: ${viewChangedDetails.visibleDates.first.weekday})");
      appState.visibleDate = viewChangedDetails.visibleDates.first;
      updateCalendarData(appState, const Duration(days: 7));
    } catch (e) {
      debugPrint(
          "=====onCalendarViewChanged: Error updating the calendar data: ${e.runtimeType}");
    }
  }

// Code for future development
// Add an appointment to the calendar or remove it if already exists.
// void onCalendarTapped(CalendarTapDetails calendarTapDetails) {
//   // Only appointment view is enabled for editing, so return if any other view is tapped.
//   if (calendarTapDetails.targetElement != CalendarElement.calendarCell &&
//       calendarTapDetails.targetElement != CalendarElement.appointment) {
//     return;
//   }
//
//   _selectedAppointment = null;
//   _isAllDay = false;
//   _selectedColorIndex = 0;
//   _subject = '';
//   _notes = '';
//
//   // If there is exactly one appointment tapped
//   if (calendarTapDetails.appointments != null &&
//       calendarTapDetails.appointments!.length == 1) {
//     final Meeting meetingDetails = calendarTapDetails.appointments![0];
//     // Get the details of the tapped appointment
//     _startDate = meetingDetails.from; // Set the start date of the appointment
//     _endDate = meetingDetails.to; // Set the end date of the appointment
//     _isAllDay = meetingDetails
//         .isAllDay; // Set whether the appointment is an all-day event
//
//     _selectedColorIndex = _colorCollection.indexOf(meetingDetails
//         .background); // Set the selected color index based on the appointment's background color
//
//     // TODO Improve color handling between device calendar and static list - 0x28
//     // Add color from device calendar to the color collection if it is not already present
//     if (_selectedColorIndex < 0) {
//       debugPrint(
//           "=====onCalendarTapped: Adding new color ${meetingDetails.background} to _colorCollection");
//       _colorCollection.add(meetingDetails.background);
//       _colorNames.add(meetingDetails.background.value.toString());
//       _selectedColorIndex =
//           _colorCollection.indexOf(meetingDetails.background);
//     }
//
//     _subject = meetingDetails.eventName == '(No title)'
//         ? '' // If the appointment has no title, set the subject to an empty string
//         : meetingDetails
//             .eventName; // Otherwise, set the subject to the event name
//     _notes = meetingDetails
//         .description; // Set the notes to the appointment's description
//     _selectedAppointment = meetingDetails; // Store the selected appointment
//   } else {
//     // If no appointment is tapped or multiple appointments are tapped
//     final DateTime date = calendarTapDetails.date!;
//     _startDate = date; // Set the start date to the tapped date
//     _endDate = date.add(const Duration(
//         hours: 1)); // Set the end date to one hour after the start date
//   }
//   // Set the start and end times based on the start and end dates
//   _startTime = TimeOfDay(hour: _startDate.hour, minute: _startDate.minute);
//   _endTime = TimeOfDay(hour: _endDate.hour, minute: _endDate.minute);
//   // Navigate to the AppointmentEditor screen
//   Navigator.push<Widget>(
//     context,
//     MaterialPageRoute(
//         builder: (BuildContext context) => const AppointmentEditor()),
//   );
// }
}

// Initialize and update calendar data
Future<void> loadCalendarData(AppState appState, Duration timeToFetch,
    [Duration backwards = const Duration(days: 0),
    DateTime? specificDate]) async {
  debugPrint("=====loadCalendarData");

  // Initializing the calendar if not already initialized or no calendar has been found before (in case of a user caused changed)
  if (appState.calendarsInitialized == false || calendars.isEmpty) {
    debugPrint(
        "=====loadCalendarData: Calendars are not initialized yet. Initializing them.");
    await initCalendars(appState);
  } else {
    debugPrint(
        "=====loadCalendarData: List of calendars is already initialized and has ${calendars.length} calendars");
  }

  // Update the calendar data source with the current appointments
  try {
    debugPrint("=====loadCalendarData: Updating calendar data");
    if (specificDate == null) {
      updateCalendarData(appState, timeToFetch, backwards);
    } else {
      updateCalendarData(appState, timeToFetch, backwards, specificDate);
    }
  } catch (e) {
    debugPrint("=====loadCalendarData: Error loading app state: ${e.runtimeType}");
  }
}

// Update the calendar data source with the current appointments
void updateCalendarData(AppState appState, Duration timeToFetch,
    [Duration backwards = const Duration(days: 0),
    DateTime? specificDate]) async {
  debugPrint("=====updateCalendarData");

  // Set mutex to prevent calculating scheduled meetings while reading calendar data
  try {
    appState.isReadingCalendarMutex = true;
  } catch (e) {
    debugPrint("=====updateCalendarData: Error setting mutex: ${e.runtimeType}");
    return; // Return early on error
  }

  List<Meeting> meetings = [];
  try {
    DateTime startOfWeek;
    if (specificDate != null) {
      startOfWeek = getStartOfWeek(appState, specificDate);
    } else {
      startOfWeek = getStartOfWeek(appState, appState.visibleDate);
    }

    // Check if current week needs fetching
    bool doesNeedFetching = true;
    try {
      if (specificDate == null &&
          await appState.isCalendarWeekFetched(appState.visibleDate)) {
        doesNeedFetching = false;
      }
    } catch (e) {
      debugPrint(
          "=====updateCalendarData: Error loading list of fetched calendar entries: ${e.runtimeType}");
    }

    if (appState.firstUpdateOfCalendar) {
      doesNeedFetching = true;
    }

    if (!doesNeedFetching) {
      debugPrint(
          "=====updateCalendarData: No need to update the calendar. First update: ${appState.firstUpdateOfCalendar}, Visible date: ${appState.visibleDate} (Fetched before: ${appState.isCalendarWeekFetched(appState.visibleDate)})");
    } else {
      debugPrint(
          "=====updateCalendarData: ${appState.visibleDate} has not been fetched. First update: ${appState.firstUpdateOfCalendar}, Visible date: ${appState.visibleDate}, Fetched weeks: ${appState.fetchedCalendarWeeks}");
      try {
        debugPrint("=====updateCalendarData: Reading calendar data from OS");
        meetings = await getCalendarEntries(appState,
            startOfWeek.subtract(backwards), startOfWeek.add(timeToFetch));
      } catch (e) {
        debugPrint(
            "=====updateCalendarData: Error reading calendar data from OS: ${e.runtimeType}");
      }
      appState.meetings += meetings;
      appState.fetchedCalendarWeeks.add(appState.visibleDate);

      // If the calendar has been initialized and fetched, set the first update flag to false
      if (appState.meetings.isNotEmpty) {
        debugPrint(
            "=====updateCalendarData: Successfully updated calendar data the first time");
        appState.firstUpdateOfCalendar = false;
      }
    }
  } catch (e) {
    debugPrint("=====updateCalendarData: Error loading app state: ${e.runtimeType}");
  }

  try {
    debugPrint(
        "=====updateCalendarData: Writing data (${appState.meetings.length} entries) to calendar data source");
    _events.appointments?.clear();
    _events.appointments?.addAll(appState.meetings);
    _events.notifyListeners(CalendarDataSourceAction.reset, meetings);
  } catch (e) {
    debugPrint("=====updateCalendarData: Error updating data source: ${e.runtimeType}");
  }

  // Release the mutex
  try {
    appState.isReadingCalendarMutex = false;
  } catch (e) {
    debugPrint("=====updateCalendarData: Error loading app state: ${e.runtimeType}");
  }
}
