import 'dart:async';
import 'dart:convert';

import 'package:calendar_view/calendar_view.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Dependencies of calendar.dart
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
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

/// New feature (user request): the "X" that marks an ignored event's tile,
/// on top of the grey `meetingToCalendarEvent` already gives it. A named
/// widget of its own (rather than an inline `Icon`) purely so a test can
/// find it by type without depending on icon data/colour, which is
/// incidental to the requirement ("grayed out and with an X on it").
class IgnoredEventMark extends StatelessWidget {
  const IgnoredEventMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.close, color: Colors.white70, size: 28),
    );
  }
}

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
class _ScreenScheduleState extends State<ScreenSchedule> {
  _ScheduleView _view = _ScheduleView.week;
  late DateTime _displayDate;

  /// Bumped only when the date is set *programmatically* (first build, Today
  /// button), never when the user pages. It is part of the view's key, and the
  /// key is what forces a fresh State so `initialDay` is re-read.
  ///
  /// The date itself must NOT be in that key: paging writes `visibleDate`,
  /// which notifies listeners, which rebuilds this screen with a new key - so
  /// every swipe tore the calendar down and rebuilt it, resetting the time
  /// grid's scroll position to midnight and killing the fling mid-flight.
  int _jumpCounter = 0;

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

  /// The calendar's colours, derived from the app's own `ColorScheme`.
  ///
  /// calendar_view ships its own palette - a bright red header, pink grid
  /// lines, and weekday/timeline text in a fixed dark grey. On the first run of
  /// the migrated screen that is exactly what appeared, and in dark mode the
  /// weekday strip and the hour labels were barely legible against the dark
  /// background. SfCalendar had been handed `colorScheme.surface` for those
  /// surfaces, so the replacement has to be told the same thing.
  ///
  /// Supplied as Flutter `ThemeExtension`s, which is how the widgets actually
  /// read them (`Theme.of(context).extension<WeekViewThemeData>()`, see
  /// calendar_view's `extensions.dart`). The package's own
  /// `CalendarThemeProvider` looks like the way to do this and is **not**: a
  /// theme handed to it never reaches the rendering, which a passing test and
  /// an unchanged screenshot proved the hard way.
  ///
  /// One mechanism instead of the individual widget parameters, because these
  /// extensions cover everything - including the weekday and timeline text
  /// colours, which have no widget-level parameter at all and were the two that
  /// went near-invisible in dark mode.
  List<ThemeExtension<dynamic>> _calendarTheme(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = context.watch<AppState>().accentColor;
    final grid = Theme.of(context).dividerColor;
    // The weekday strip and the month grid sit slightly off the page so the
    // calendar body still reads as a surface of its own.
    final tile = scheme.surfaceContainerHighest;

    return <ThemeExtension<dynamic>>[
      WeekViewThemeData(
        weekDayTileColor: tile,
        weekDayTextColor: scheme.onSurface,
        hourLineColor: grid,
        halfHourLineColor: grid,
        quarterHourLineColor: grid,
        liveIndicatorColor: accent,
        pageBackgroundColor: scheme.surface,
        headerIconColor: scheme.onSurface,
        headerTextColor: scheme.onSurface,
        headerBackgroundColor: scheme.surface,
        timelineTextColor: scheme.onSurfaceVariant,
        borderColor: grid,
        verticalLinesColor: grid,
      ),
      DayViewThemeData(
        hourLineColor: grid,
        halfHourLineColor: grid,
        quarterHourLineColor: grid,
        pageBackgroundColor: scheme.surface,
        liveIndicatorColor: accent,
        headerIconColor: scheme.onSurface,
        headerTextColor: scheme.onSurface,
        headerBackgroundColor: scheme.surface,
        timelineTextColor: scheme.onSurfaceVariant,
      ),
      MonthViewThemeData(
        cellInMonthColor: scheme.surface,
        cellNotInMonthColor: tile,
        cellTextColor: scheme.onSurface,
        cellBorderColor: grid,
        weekDayTileColor: tile,
        weekDayTextColor: scheme.onSurface,
        weekDayBorderColor: grid,
        headerIconColor: scheme.onSurface,
        headerTextColor: scheme.onSurface,
        headerBackgroundColor: scheme.surface,
        cellHighlightColor: accent,
      ),
      MultiDayViewThemeData(
        multiDayTileColor: tile,
        multiDayTextColor: scheme.onSurface,
        hourLineColor: grid,
        halfHourLineColor: grid,
        quarterHourLineColor: grid,
        liveIndicatorColor: accent,
        pageBackgroundColor: scheme.surface,
        headerIconColor: scheme.onSurface,
        headerTextColor: scheme.onSurface,
        headerBackgroundColor: scheme.surface,
        timelineTextColor: scheme.onSurfaceVariant,
        borderColor: grid,
        verticalLinesColor: grid,
      ),
    ];
  }

  /// Moves the calendar to [date] and tells AppState, which paging does for
  /// itself. Without the second half the Today button moved the view but left
  /// `visibleDate` on the week the user had swiped to, so leaving the screen
  /// and coming back jumped there again.
  void _jumpTo(DateTime date) {
    setState(() {
      _displayDate = date;
      _jumpCounter++;
    });
    appState.visibleDate = date;
    updateCalendarData(appState, const Duration(days: 7));
  }

  /// `timeFormat: 'HH:mm'` in SfCalendar terms. calendar_view's default hour
  /// label is "1 PM", which ignores the phone's 24-hour setting and is simply
  /// wrong for most of this app's users. `DayView` offers no string-only hook,
  /// so the whole mark is built here - which also lets the label take its
  /// colour from the theme like every other calendar surface.
  ///
  /// docs/TODO.md T-52.2: this used to hardcode 'HH:mm' (24h) regardless of
  /// the device's own setting - wrong for exactly the users
  /// [MediaQuery.alwaysUse24HourFormat] is false for.
  /// `MediaQuery.of(context).alwaysUse24HourFormat` is Flutter's own reading
  /// of that setting (populated from the platform's `is24HourFormat` on
  /// Android) - the same source `showTimePicker` itself defaults to, so this
  /// follows the identical rule as every other time display already in the
  /// app rather than introducing a second, independent format decision.
  Widget _timeLineMark(DateTime date) {
    final format =
        MediaQuery.of(context).alwaysUse24HourFormat ? 'HH:mm' : 'h:mm a';
    return Transform.translate(
      offset: const Offset(0, -7.5),
      child: Padding(
        padding: const EdgeInsets.only(right: 7),
        child: Text(
          DateFormat(format).format(date),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// New feature (user request): draws the same tile calendar_view always
  /// has (`DefaultEventTile` - the grey background from `meetingToCalendarEvent`
  /// already does the "grayed out" half), plus a centred X on top when every
  /// event in this slot is ignored. Only "every" rather than "any": two
  /// overlapping events, one ignored and one not, would otherwise mark the
  /// live one as dead too - `DefaultEventTile` itself has no per-event
  /// styling hook for that rarer case, so it is left with just its own grey
  /// tint and no X, rather than drawn wrong.
  Widget _eventTileBuilder(
    DateTime date,
    List<CalendarEventData<Meeting>> events,
    Rect boundary,
    DateTime startDuration,
    DateTime endDuration,
  ) {
    final tile = DefaultEventTile<Meeting>(
      date: date,
      events: events,
      boundary: boundary,
      startDuration: startDuration,
      endDuration: endDuration,
    );
    final allIgnored = events.isNotEmpty &&
        events.every(
            (e) => e.event != null && appState.isEventIgnored(e.event!));
    if (!allIgnored) return tile;
    return Stack(
      fit: StackFit.expand,
      children: [
        tile,
        const IgnoredEventMark(),
      ],
    );
  }

  /// Opens the ignore/un-ignore sheet for a tap on the day/week views, where
  /// several overlapping events can land on the same tap.
  void _onEventTap(List<CalendarEventData<Meeting>> events, DateTime date) {
    final meetings = events
        .map((e) => e.event)
        .whereType<Meeting>()
        .toList(growable: false);
    if (meetings.isEmpty) return;
    _showIgnoreEventSheet(meetings);
  }

  /// docs/TODO.md T-53: which calendars feed the Schedule display and
  /// scheduling. Same shape as [_showIgnoreEventSheet] just above -
  /// `StatefulBuilder`-wrapped `CheckboxListTile`s in a modal sheet, so the
  /// sheet stays open while the user toggles more than one entry.
  void _showCalendarSelectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Calendars', style: TextStyle(fontSize: 18.0)),
            ),
            if (calendars.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No calendars found on this device.'),
              ),
            for (final calendar in calendars)
              StatefulBuilder(
                builder: (context, setSheetState) => CheckboxListTile(
                  title: Text(
                    // docs/TODO.md T-89: regularly the user's own account
                    // email address (Google/Exchange) - never logged, but
                    // fine to show here since it's the user's own device.
                    calendar.name ?? calendar.id ?? 'Unnamed calendar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: appState.isCalendarSelected(calendar.id!),
                  onChanged: (value) {
                    appState.setCalendarSelected(calendar.id!, value ?? true);
                    setSheetState(() {});
                    // The same trigger _showIgnoreEventSheet uses above: a
                    // change here feeds hardFloor derivation (replan.dart)
                    // and must take effect immediately, not on the next
                    // incidental replan.
                    runCheckpointSafely(appState,
                        trigger: CheckpointTrigger.settingsChanged);
                    unawaited(resyncCalendarData(appState));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showIgnoreEventSheet(List<Meeting> meetings) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final meeting in meetings)
              StatefulBuilder(
                builder: (context, setSheetState) => SwitchListTile(
                  title: Text(
                    meeting.eventName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Ignore for scheduling'),
                  value: appState.isEventIgnored(meeting),
                  onChanged: (value) {
                    appState.setEventIgnored(meeting, value);
                    setSheetState(() {});
                    setState(() => _syncEventsFromAppState(appState));
                    // New feature (user request): consulted by hardFloor
                    // derivation (replan.dart) - a change must take effect
                    // immediately, the same as any other setting that feeds
                    // the computation (FR-21's disabledDays toggle uses the
                    // identical trigger for the identical reason).
                    runCheckpointSafely(appState,
                        trigger: CheckpointTrigger.settingsChanged);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    // The key makes a view switch rebuild the widget from scratch, so the newly
    // chosen view opens on the date the user was looking at rather than today.
    final key = ValueKey<String>('${_view.name}-$_jumpCounter');

    switch (_view) {
      case _ScheduleView.day:
        return DayView<Meeting>(
          key: key,
          controller: _events,
          initialDay: _displayDate,
          onPageChange: _onPageChange,
          timeLineBuilder: _timeLineMark,
          eventTileBuilder: _eventTileBuilder,
          onEventTap: _onEventTap,
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
          timeLineBuilder: _timeLineMark,
          eventTileBuilder: _eventTileBuilder,
          onEventTap: _onEventTap,
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
          // Ignore-toggle intentionally NOT wired up here (docs/TODO.md
          // T-149): calendar_view 2.0.0's MonthView has a real generics bug -
          // passing a typed (non-`Object?`) `onEventTap` throws
          // "type '(CalendarEventData<Meeting>, DateTime) => void' is not a
          // subtype of type '(CalendarEventData<Object?>, DateTime) =>
          // void)?'" the moment a month cell with an event renders, because
          // `FilledCell`'s internal tap wiring loses the type parameter
          // somewhere between `MonthViewBuilders<T>` and the cell. There is
          // also no eventTileBuilder equivalent for the month grid's compact
          // per-day event list, so the X mark day/week view gets would need
          // different treatment here anyway. The grey colour from
          // meetingToCalendarEvent still shows in month view regardless -
          // only the tap-to-toggle interaction is unavailable there.
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
            onPressed: () => _jumpTo(DateTime.now()),
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
          // docs/TODO.md T-53: a checkable calendar list, reachable from a
          // corner button in the app bar.
          IconButton(
            tooltip: 'Calendars',
            icon: const Icon(Icons.event_note),
            onPressed: _showCalendarSelectionSheet,
          ),
        ],
      ),
      // Define the body of the screen.
      body: CalendarControllerProvider<Meeting>(
        controller: _events,
        child: Theme(
          data: Theme.of(context).copyWith(
            extensions: _calendarTheme(context),
          ),
          child: Builder(builder: _buildCalendar),
        ),
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
    debugPrint(
        "=====loadCalendarData: Error loading app state: ${e.runtimeType}");
  }
}

/// Rebuilds `_events` from `appState.meetings`, picking up the current
/// ignored-state colouring (`meetingToCalendarEvent`'s `ignored` parameter) -
/// shared by `updateCalendarData` (after a calendar fetch) and by toggling an
/// event's ignored state (where `appState.meetings` itself hasn't changed, so
/// there's nothing to re-fetch, but the tile colours still have to update
/// immediately rather than waiting for the next fetch).
void _syncEventsFromAppState(AppState appState) {
  _events.removeWhere((_) => true);
  _events.addAll(appState.meetings
      .map((m) =>
          meetingToCalendarEvent(m, ignored: appState.isEventIgnored(m)))
      .toList());
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
    debugPrint(
        "=====updateCalendarData: Error setting mutex: ${e.runtimeType}");
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
      // docs/TODO.md T-55: recorded by the start of the week, matching
      // `preloadCalendarData`'s convention - `isCalendarWeekFetched` compares
      // against that, not against an arbitrary day within the week.
      appState.fetchedCalendarWeeks.add(startOfWeek);

      // If the calendar has been initialized and fetched, set the first update flag to false
      if (appState.meetings.isNotEmpty) {
        debugPrint(
            "=====updateCalendarData: Successfully updated calendar data the first time");
        appState.firstUpdateOfCalendar = false;
      }
    }
  } catch (e) {
    debugPrint(
        "=====updateCalendarData: Error loading app state: ${e.runtimeType}");
  }

  try {
    debugPrint(
        "=====updateCalendarData: Writing data (${appState.meetings.length} entries) to calendar data source");
    // Rebuild the whole set rather than diffing: the fetch above appends to
    // `appState.meetings`, so the list is the single source of truth and a
    // partial update would drift from it.
    _syncEventsFromAppState(appState);
  } catch (e) {
    debugPrint(
        "=====updateCalendarData: Error updating data source: ${e.runtimeType}");
  }

  // Release the mutex
  try {
    appState.isReadingCalendarMutex = false;
  } catch (e) {
    debugPrint(
        "=====updateCalendarData: Error loading app state: ${e.runtimeType}");
  }
}
