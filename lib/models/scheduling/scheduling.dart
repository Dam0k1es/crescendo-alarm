import 'package:flutter/material.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

/// Finds the earliest of [alarmTimes] (compared by time-of-day only, ignoring
/// date), where two times within [sleepGoalMinutes] minutes of each other are
/// resolved by which one is "earlier considering wraparound" rather than by
/// raw clock order - so a 23:00 alarm can count as earlier than a 01:00 one
/// if they're close enough to be part of the same sleep cycle.
///
/// Extracted out of [Scheduler] so it's unit-testable without an [AppState] -
/// see test/scheduling_test.dart. [sleepGoalMinutes] is the sleep goal
/// already resolved to minutes (hour * 60 + minute) from `appState.sleepGoal`
/// (a [TimeOfDay]).
DateTime getEarliestEvent(List<DateTime> alarmTimes, int sleepGoalMinutes) {
  // Sort the list of alarmTimes
  alarmTimes.sort((a, b) {
    int aMinutes = a.hour * 60 + a.minute;
    int bMinutes = b.hour * 60 + b.minute;
    return aMinutes.compareTo(bMinutes);
  });

  debugPrint(
      "=====getEarliestEvent: Earliest event by sorting is ${alarmTimes.first}");

  // Initialize earliest time with the first element in sorted list
  DateTime earliest = alarmTimes.first;

  // Iterate through alarmTimes to find the earliest event considering sleep goal
  for (var time in alarmTimes) {
    if (_isEarlierConsideringSleepGoal(time, earliest, sleepGoalMinutes)) {
      earliest = time;
    }
  }

  debugPrint("=====getEarliestEvent: Earliest event is $earliest");
  return earliest;
}

bool _isEarlierConsideringSleepGoal(DateTime a, DateTime b, int sleepGoalMinutes) {
  // Calculate the total minutes of the day for both times
  int aMinutes = a.hour * 60 + a.minute;
  int bMinutes = b.hour * 60 + b.minute;

  // Calculate the absolute difference in minutes between a and b
  int diff = (bMinutes - aMinutes).abs();

  // Calculate the difference if considering wrapping around the day
  int wrappedDiff = (24 * 60 - aMinutes + bMinutes).abs();

  // Check if a is earlier than b considering the sleepGoal
  // The condition is either:
  // 1. a is earlier than b and the difference is within the sleepGoal range
  // 2. b is earlier than a and the wrapped difference is within the sleepGoal range
  return (aMinutes < bMinutes && diff < sleepGoalMinutes) ||
      (bMinutes < aMinutes && wrappedDiff < sleepGoalMinutes);
}

/// Returns the start time of the earliest non-all-day [meetings] entry that
/// falls on [date], or null if there is none.
///
/// Extracted out of [Scheduler] so it's unit-testable without an [AppState] -
/// see test/scheduling_test.dart.
DateTime? getStartTimeForDate(DateTime date, List<Meeting> meetings) {
  Meeting? firstAppointment;
  for (Meeting appointment in meetings) {
    bool appointmentOnSameDay = (appointment.isAllDay == false &&
        appointment.from.year == date.year &&
        appointment.from.month == date.month &&
        appointment.from.day == date.day);
    if (appointmentOnSameDay) {
      bool earlierMeetingFound = (firstAppointment == null ||
          appointment.from.isBefore(firstAppointment.from));
      if (earlierMeetingFound) {
        firstAppointment = appointment;
      }
    }
  }

  if (firstAppointment == null) {
    debugPrint("=====getStartTimeForDate: No appointment on $date");
    return null;
  } else {
    debugPrint(
        "=====getStartTimeForDate: First appointment on $date is ${firstAppointment.eventName}");
  }

  return firstAppointment.from;
}

/// Estimates a wake-up time for every entry in [alarmTimes] that falls more
/// than [wakeUpOffset] after [earliestAlarm], replacing it with
/// [earliestAlarm]'s time-of-day (plus [wakeUpOffset]) on that entry's own
/// date. Returns null if 7 or more entries needed estimating (scheduling is
/// abandoned rather than producing a schedule built mostly of guesses).
///
/// Extracted out of [Scheduler] so it's unit-testable without an [AppState] -
/// see test/scheduling_test.dart. Note: the comparison against
/// [earliestAlarm] is against an absolute `DateTime` (date and time both),
/// not time-of-day alone - see docs/TODO.md T-02 for the consequence this
/// has for schedules spanning more than one day, which this function
/// preserves rather than silently fixes.
List<DateTime>? adjustAlarmTimes(
    List<DateTime> alarmTimes, DateTime earliestAlarm, Duration wakeUpOffset) {
  List<DateTime> adjustedAlarmTimes = [];

  DateTime offset = earliestAlarm.add(wakeUpOffset);

  // Watch how many alarms are scheduled by estimation
  int numberOfAdjustedAlarms = 0;

  for (DateTime alarmTime in alarmTimes) {
    // Calculate the time difference between the alarmTime and the earliestAlarm
    if (alarmTime.isAfter(offset)) {
      debugPrint(
          "=====adjustAlarmTimes: The difference between $alarmTime and $earliestAlarm is to large");
      // If an schedule is to far off add the offset to the earliest alarm time
      alarmTime = DateTime(
          alarmTime.year,
          alarmTime.month,
          alarmTime.day,
          earliestAlarm.hour,
          earliestAlarm.minute + wakeUpOffset.inMinutes,
          earliestAlarm.second);
      numberOfAdjustedAlarms += 1;
    }
    // Add the alarm with or without offset
    adjustedAlarmTimes.add(alarmTime);
  }

  if (numberOfAdjustedAlarms >= 7) {
    debugPrint("=====_adjustAlarmTimes: Too many alarm estimations");
    return null;
  } else {
    return adjustedAlarmTimes;
  }
}

class Scheduler {
  late DateTime earliestAlarm;

  Future<void> scheduleAlarms(AppState appState) async {
    // Check if the calendar data is being read
    if (appState.isReadingCalendarMutex == true) {
      debugPrint(
          "=====scheduleAlarms: Currently reading calendar data. Aborting the scheduling of new alarms.");
      try {
        Notifications notifications = Notifications();
        notifications.scheduleNotification(
            title: 'WakeyWakey',
            body:
                'Currently reading calendar data. Aborting the scheduling of new alarms.');
      } catch (e) {
        debugPrint(
            "=====scheduleAlarms: Error while scheduling the notification. Error: $e");
      }
      return;
    }

    // Delete the previously scheduled alarms
    List<ScheduledAlarm> scheduledAlarmsCopy =
        List.from(appState.scheduledAlarms);
    for (ScheduledAlarm alarm in scheduledAlarmsCopy) {
      await appState.removeAlarm(alarm);
    }

    // Create list of DateTimes for alarms
    DateTime? startTime;
    List<DateTime>? alarmTimes = [];

    // TODO durationToGetReady per weekday - 0x399
    // Calculate the offset from the earliest calendar entry
    Duration durationToWakeUp =
        durationFromTimeOfDay(appState.durationToWakeUp);
    Duration durationToGetReady =
        durationFromTimeOfDay(appState.durationToGetReady);
    Duration durationBeforeFirstMeeting = durationToWakeUp + durationToGetReady;
    debugPrint(
        "=====scheduleAlarms: Offset: $durationBeforeFirstMeeting. Time to wake up: $durationToWakeUp. Time to get ready is $durationToGetReady");

    // Iterate over pre calculation range
    // TODO User changeable pre calculation range of scheduled alarms - 0x392
    // TODO Configure durationToWakeUpLate to be considered even if an appointment exists -  0x52
    for (int day = 0; day < 7; day++) {
      startTime = getStartTimeForDate(
          DateTime.now().add(Duration(days: day)), appState.meetings);
      if (startTime != null) {
        debugPrint(
            "=====scheduleAlarms: You have to WakeyWakey at $startTime on ${DateTime.now().add(Duration(days: day))}");
        startTime = startTime.subtract(durationBeforeFirstMeeting);
        alarmTimes.add(startTime);
      } else {
        debugPrint(
            "=====scheduleAlarms: You do not have to WakeyWakey on ${DateTime.now().add(Duration(days: day))}");
        // Add an alarm anyway to keep the sleep cycle consistent
        DateTime problematicDay = DateTime.now().add(Duration(days: day));
        // Set the DateTime to the day of week with 23:59 as time (a value that will not be picked otherwise)
        alarmTimes.add(DateTime(problematicDay.year, problematicDay.month,
            problematicDay.day, 23, 59));
      }
    }

    // Copy non null values to separate list
    List<DateTime>? existingTimes = alarmTimes
        .where((dateTime) => !(dateTime.hour == 23 && dateTime.minute == 59))
        .toList();

    if (existingTimes.isEmpty) {
      debugPrint("=====scheduleAlarms: No events in calendar. Aborting.");
      return;
    }

    // Check for the earliest alarm
    final TimeOfDay sleepGoalTimeOfDay = appState.sleepGoal;
    final int sleepGoalMinutes =
        sleepGoalTimeOfDay.hour * 60 + sleepGoalTimeOfDay.minute;
    earliestAlarm = getEarliestEvent(List.from(existingTimes), sleepGoalMinutes);

    // Calculate the time to wake up for days with late or no calendar entries
    alarmTimes = adjustAlarmTimes(
        alarmTimes, earliestAlarm, durationFromTimeOfDay(appState.wakeUpSteps));

    if (alarmTimes != null) {
      // Add alarms for every day
      for (DateTime startTime in alarmTimes) {
        ScheduledAlarm newAlarm;
        try {
          debugPrint("=====scheduleAlarms: Setting alarm for $startTime");
          newAlarm = ScheduledAlarm(
              time: startTime,
              title: 'WakeyWakey',
              enabled: true,
              gentlewake: appState.gentleWakeUpEnabled,
              tone: appState.selectedTone,
              id: getRandom());
        } catch (e) {
          debugPrint(
              "=====scheduleAlarms: Error while creating the alarm. Error: $e");
          debugPrint("=====scheduleAlarms: Creating alarm with default values");
          newAlarm = ScheduledAlarm(
              time: startTime,
              title: 'WakeyWakey',
              enabled: true,
              gentlewake: false,
              tone: 'assets/sounds/wake_up.mp3',
              id: getRandom());
        }
        await appState.addAlarm(newAlarm);
      }
    } else {
      debugPrint(
          "=====scheduleAlarms: Could not get enough calendar entries to set reasonable alarm schedule");
      try {
        Notifications notifications = Notifications();
        notifications.scheduleNotification(
            title: 'WakeyWakey',
            body:
                'Could not get enough calendar entries to set reasonable alarm schedule.');
      } catch (e) {
        debugPrint(
            "=====scheduleAlarms: Error while scheduling the notification. Error: $e");
      }
    }

    // setScheduledAlarmToNow(appState);
  }

  // TODO Performance: presorted lists? - 0x26

  // Get the DateTime of the next alarm
  static DateTime nextAlarmTime(AppState appState) {
    // Set an alarm in the future to be compared to other (probably closer) alarms
    DateTime earliestAlarmTime = DateTime.now().add(const Duration(days: 7));

    // Iterate over all ManualAlarms and save the earliest alarm.time
    // ManualAlarm.time is a TimeOfDay (not a DateTime), so it must be
    // resolved to its next actual occurrence (today, or tomorrow if that
    // time of day has already passed) before it can be compared.
    for (ManualAlarm alarm in appState.manualAlarms) {
      DateTime now = DateTime.now();
      DateTime alarmDateTime = DateTime(
          now.year, now.month, now.day, alarm.time.hour, alarm.time.minute);
      if (alarmDateTime.isBefore(now)) {
        alarmDateTime = alarmDateTime.add(const Duration(days: 1));
      }
      if (alarmDateTime.isBefore(earliestAlarmTime)) {
        earliestAlarmTime = alarmDateTime;
      }
    }

    // Iterate over all ScheduledAlarms and save the earliest alarm.time
    for (ScheduledAlarm alarm in appState.scheduledAlarms) {
      if (alarm.time.isBefore(earliestAlarmTime)) {
        earliestAlarmTime = alarm.time;
      }
    }

    return earliestAlarmTime;
  }

  Future<void> setScheduledAlarmToNow(AppState appState) async {
    ScheduledAlarm newAlarm;
    DateTime now = DateTime.now();
    now = now.add(const Duration(minutes: 1));
    int id = getRandom();
    try {
      newAlarm = ScheduledAlarm(
          time: now,
          title: 'WakeyWakey',
          enabled: true,
          gentlewake: appState.gentleWakeUpEnabled,
          tone: appState.selectedTone,
          id: id);
    } catch (e) {
      debugPrint(
          "=====scheduleAlarms: Error while creating the alarm. Error: $e");
      debugPrint("=====scheduleAlarms: Creating alarm with default values");
      newAlarm = ScheduledAlarm(
          time: now,
          title: 'WakeyWakey',
          enabled: true,
          gentlewake: false,
          tone: 'assets/sounds/wake_up.mp3',
          id: id);
    }
    await appState.addAlarm(newAlarm);
  }
}
