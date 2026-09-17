import 'dart:convert';

import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Dependencies of calendar.dart
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/utils.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

part 'calendar.dart';

part 'meeting_data.dart';

/// The appointments the calendar draws.
///
/// docs/TODO.md T-05: this used to be a Syncfusion `CalendarDataSource`, whose
/// package may not be used without a community or commercial licence and could
/// therefore not travel inside a GPLv3 APK. `EventController` is the
/// calendar_view (MIT) equivalent.
final EventController<Meeting> _events = EventController<Meeting>();

late AppState appState;

/// The views the screen offers, unchanged from what SfCalendar's `allowedViews`
/// offered - a migration should not quietly cost the user a feature.
enum _ScheduleView {
  day('Day'),
  week('Week'),
  workWeek('Work week'),
  month('Month');

  const _ScheduleView(this.label);
  final String label;
}

// Define the screen schedule widget.
class ScreenSchedule extends StatefulWidget {
  const ScreenSchedule({super.key});

  @override
  State<ScreenSchedule> createState() => _ScreenScheduleState();
}

// Define the screen schedule state.
class _ScreenScheduleState extends State<ScreenSchedule>
    with SingleTickerProviderStateMixin {
  _ScheduleView _view = _ScheduleView.week;
  late DateTime _displayDate;

  @override
  void initState() {
    debugPrint("=====initState");
    super.initState();
    appState = Provider.of<AppState>(context, listen: false);
    _displayDate = appState.visibleDate;
  }

  /// Called when the calendar has paged to another week/day/month.
  ///
  /// The date arrives as the first day of the new page - the same thing
  /// SfCalendar's `visibleDates.first` used to deliver, so the downstream
  /// fetching logic is unchanged.
  void _onPageChange(DateTime date, int page) {
    // After the frame, exactly as before: updateCalendarData writes to AppState
    // and would otherwise notify listeners during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        debugPrint(
            "=====onCalendarViewChanged: Visible date is $date (Weekday: ${date.weekday})");
        _displayDate = date;
        appState.visibleDate = date;
        updateCalendarData(appState, const Duration(days: 7));
      } catch (e) {
        debugPrint(
            "=====onCalendarViewChanged: Error updating the calendar data: ${e.runtimeType}");
      }
    });
  }

  Widget _buildCalendar(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    // The key makes a view switch rebuild the widget from scratch, so the newly
    // chosen view opens on the date the user was looking at rather than today.
    final key = ValueKey<String>('${_view.name}-$_displayDate');

    switch (_view) {
      case _ScheduleView.day:
        return DayView<Meeting>(
          key: key,
          controller: _events,
          initialDay: _displayDate,
          onPageChange: _onPageChange,
          backgroundColor: background,
          showLiveTimeLineInAllDays: true,
          heightPerMinute: 1,
        );
      case _ScheduleView.week:
      case _ScheduleView.workWeek:
        return WeekView<Meeting>(
          key: key,
          controller: _events,
          initialDay: _displayDate,
          onPageChange: _onPageChange,
          backgroundColor: background,
          startDay: WeekDays.monday,
          // `firstDayOfWeek: 1` in SfCalendar terms.
          weekDays: _view == _ScheduleView.workWeek
              ? const [
                  WeekDays.monday,
                  WeekDays.tuesday,
                  WeekDays.wednesday,
                  WeekDays.thursday,
                  WeekDays.friday,
                ]
              : WeekDays.values,
          heightPerMinute: 1,
        );
      case _ScheduleView.month:
        return MonthView<Meeting>(
          key: key,
          controller: _events,
          monthViewStyle: MonthViewStyle(
            initialMonth: _displayDate,
            startDay: WeekDays.monday,
          ),
          monthViewBuilders: MonthViewBuilders(onPageChange: _onPageChange),
        );
    }
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
        actions: [
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () => setState(() => _displayDate = DateTime.now()),
          ),
          PopupMenuButton<_ScheduleView>(
            tooltip: 'Calendar View',
            icon: const Icon(Icons.calendar_view_week),
            initialValue: _view,
            onSelected: (value) => setState(() => _view = value),
            itemBuilder: (context) => [
              for (final view in _ScheduleView.values)
                PopupMenuItem<_ScheduleView>(
                  value: view,
                  child: Text(view.label),
                ),
            ],
          ),
        ],
      ),
      // Define the body of the screen.
      body: CalendarControllerProvider<Meeting>(
        controller: _events,
        child: _buildCalendar(context),
      ),
    );
  }
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
    // Rebuild the whole set rather than diffing: the fetch above appends to
    // `appState.meetings`, so the list is the single source of truth and a
    // partial update would drift from it.
    _events.removeWhere((_) => true);
    _events.addAll(appState.meetings.map(meetingToCalendarEvent).toList());
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
