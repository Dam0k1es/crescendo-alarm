// Copyright (C) 2026 Dam0k1es
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

int getRandom() {
  return Random().nextInt(99999999);
}

tz.TZDateTime convertToTZDateTime(DateTime dateTime, String timeZone) {
  final location = tz.getLocation(timeZone);
  return tz.TZDateTime.from(dateTime, location);
}

DateTime convertFromTZDateTime(tz.TZDateTime tzDateTime) {
  return DateTime.fromMillisecondsSinceEpoch(tzDateTime.millisecondsSinceEpoch);
}

int compareTimeOfDay(TimeOfDay a, TimeOfDay b) {
  if (a.hour != b.hour) {
    return a.hour.compareTo(b.hour);
  } else {
    return a.minute.compareTo(b.minute);
  }
}

String formatTimeOfDay(TimeOfDay time) {
  final String hour = time.hour.toString().padLeft(2, '0');
  final String minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatDateTime(DateTime dateTime) {
  String weekday = DateFormat('EEEE').format(dateTime);
  String dayOfMonth = DateFormat('d').format(dateTime);
  String month = DateFormat('MMMM').format(dateTime);
  String year = DateFormat('yyyy').format(dateTime);
  String formattedDate = '$weekday, $dayOfMonth. $month $year';
  return formattedDate;
}

Duration durationFromString(String time) {
  // Remove the ' h' at the end
  time = time.replaceAll(' h', '');

  // Split the string
  List<String> parts = time.split(':');
  int hours = int.parse(parts[0]);
  int minutes = int.parse(parts[1]);

  // Create and return a duration
  return Duration(hours: hours, minutes: minutes);
}

/// A short message to the user that disappears on its own after [duration].
///
/// `persist: false` is **not** redundant here, even with a duration set
/// (docs/TODO.md T-136). `SnackBar` pre-fills `persist` with
/// `persist ?? action != null`, and `ScaffoldMessenger` aborts its own
/// fade-out timer with `if (snackBar.persist) return;` - so a SnackBar WITH
/// an action ignores its own `duration`. The framework says so explicitly:
/// "If not provided, but the snackbar action is not null, the snackbar will
/// persist as well."
///
/// Because this function also supplies a "Dismiss" button, messages like
/// "Can not edit scheduled alarms!" stayed on screen since the very first
/// commit until the user tapped them away - even though the 5 seconds had
/// been sitting there the whole time. Whoever removes the button here, or
/// touches this line, brings that back.
void displayToast(BuildContext context, String message) {
  final scaffold = ScaffoldMessenger.of(context);
  scaffold.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 16)),
      action: SnackBarAction(
        label: 'Dismiss',
        onPressed: () {},
      ),
      duration: const Duration(seconds: 5),
      persist: false,
    ),
  );
}

void showFullScreenOverlay(BuildContext context, Widget widget) {
  debugPrint("=====showFullScreenOverlay ($widget)");
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => widget,
      fullscreenDialog: true,
    ),
  );
}

/// docs/TODO.md T-60: `preloadCalendarData` alone only ever fetches once per
/// process lifetime - nothing clears `AppState.meetings` or
/// `fetchedCalendarWeeks` afterwards, so a calendar edit made after the
/// initial preload stayed invisible in the Schedule tab until the app was
/// killed and relaunched. Called instead of [preloadCalendarData] directly
/// on every app open (`lib/main.dart`, cold start and resume alike): clears
/// both first, so the fresh fetch replaces the stale state rather than
/// appending a second copy of it on top.
Future<void> resyncCalendarData(AppState appState,
    {int pastWeeks = 2, int futureWeeks = 1}) async {
  appState.meetings = [];
  appState.fetchedCalendarWeeks = [];
  await preloadCalendarData(appState,
      pastWeeks: pastWeeks, futureWeeks: futureWeeks);
}

Future<void> preloadCalendarData(AppState appState,
    {int pastWeeks = 1, int futureWeeks = 2}) async {
  try {
    appState.firstUpdateOfCalendar = false;
  } catch (e) {
    debugPrint("=====updateCalendarData: Error loading app state: ${e.runtimeType}");
  }

  int pastDays = pastWeeks * 7;
  int futureDays = futureWeeks * 7;
  await loadCalendarData(appState, Duration(days: pastDays),
      Duration(days: futureDays), DateTime.now());

  DateTime weekStart = getStartOfWeek(DateTime.now());

  for (int i = 0; i < pastWeeks; i++) {
    DateTime startOfWeek = weekStart.subtract(Duration(days: i * 7));
    _markWeekFetched(appState, startOfWeek);
    debugPrint(
        "=====preloadCalendarData: Preloaded the week starting with $startOfWeek");
  }

  for (int i = 1; i <= futureWeeks; i++) {
    DateTime startOfWeek = weekStart.add(Duration(days: i * 7));
    _markWeekFetched(appState, startOfWeek);
    debugPrint(
        "=====preloadCalendarData: Preloaded the week starting with $startOfWeek");
  }
}

/// docs/TODO.md T-60: the loops above used to add unconditionally, so the
/// current week ended up twice in a single `preloadCalendarData` call - once
/// here, once already added by `loadCalendarData`'s own
/// `updateCalendarData(..., specificDate: DateTime.now())` call a few lines
/// above, whose successful-fetch branch records the same start-of-week date.
/// Skip a date already present rather than growing the list with duplicates.
void _markWeekFetched(AppState appState, DateTime startOfWeek) {
  final alreadyPresent = appState.fetchedCalendarWeeks.any((fetched) =>
      fetched.year == startOfWeek.year &&
      fetched.month == startOfWeek.month &&
      fetched.day == startOfWeek.day);
  if (!alreadyPresent) {
    appState.fetchedCalendarWeeks.add(startOfWeek);
  }
}

// docs/TODO.md T-42: always normalizes to Monday - there used to be a
// `startOfWeekDay` setting gating the subtraction, but it had no UI and,
// even set, never changed the target day (always Monday), only whether the
// correction ran at all - a no-op distinction, since subtracting 0 days is
// already a no-op when [dateTime] is already Monday. Removed rather than
// wired up to a UI nobody asked for.
DateTime getStartOfWeek(DateTime dateTime) {
  return dateTime.subtract(Duration(days: dateTime.weekday - 1));
}

/// docs/TODO.md T-61 (FR-18's boundary to the alarm plugin): a planned value
/// is an absolute **instant** (FR-1, typically UTC-tagged), while
/// `Alarm.set`/`AlarmSettings.dateTime` is handed a plain local wall-clock
/// `DateTime`. Building that from the instant's raw fields reinterpreted UTC
/// digits as device-local time, so on any device outside UTC+0 the alarm rang
/// off by the offset. Converting first keeps the real moment; the truncation
/// to whole minutes matches what the plugin schedules anyway.
DateTime alarmPlatformTime(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day, local.hour, local.minute);
}

Duration durationFromTimeOfDay(TimeOfDay time) {
  return Duration(hours: time.hour, minutes: time.minute);
}

// Expecting a String like '08:15'
TimeOfDay timeOfDayFromString(String data) {
  return TimeOfDay(
      hour: int.parse(data.split(':')[0]),
      minute: int.parse(data.split(':')[1]));
}
