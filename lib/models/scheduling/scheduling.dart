import 'package:flutter/material.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

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
      startTime = _getStartTimeForDate(
          DateTime.now().add(Duration(days: day)), appState);
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
    earliestAlarm = _getEarliestEvent(List.from(existingTimes), appState);

    // Calculate the time to wake up for days with late or no calendar entries
    alarmTimes = _adjustAlarmTimes(alarmTimes, appState);

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

  List<DateTime>? _adjustAlarmTimes(
      List<DateTime> alarmTimes, AppState appState) {
    // TODO User changeable option to change offset on per day basis - 0x394
    // Create a new list
    List<DateTime> adjustedAlarmTimes = [];

    // TODO User changeable offset for estimated alarms - 0x391
    Duration wakeUpOffset = durationFromTimeOfDay(appState.wakeUpSteps);

    DateTime offset = earliestAlarm.add(wakeUpOffset);

    // Watch how many alarms are scheduled by estimation
    int numberOfAdjustedAlarms = 0;

    for (DateTime alarmTime in alarmTimes) {
      // Calculate the time difference between the alarmTime and the earliestAlarm
      // TODO User changeable option to schedule or not schedule alarm on days without calendar entries - 0x393
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

    // TODO User changeable threshold for cancellation of alarm scheduling based on too many estimations - 0x395
    if (numberOfAdjustedAlarms >= 7) {
      debugPrint("=====_adjustAlarmTimes: Too many alarm estimations");
      return null;
    } else {
      return adjustedAlarmTimes;
    }
  }

  DateTime _getEarliestEvent(List<DateTime> alarmTimes, AppState appState) {
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

    // Get sleep goal from appState (assuming appState is accessible)
    TimeOfDay timeOfDaySleepGoal = appState.sleepGoal;
    int sleepGoal = timeOfDaySleepGoal.hour * 60 + timeOfDaySleepGoal.minute;

    // Iterate through alarmTimes to find the earliest event considering sleep goal
    for (var time in alarmTimes) {
      if (_isEarlierConsideringSleepGoal(time, earliest, sleepGoal)) {
        earliest = time;
      }
    }

    debugPrint("=====getEarliestEvent: Earliest event is $earliest");
    return earliest;
  }

  bool _isEarlierConsideringSleepGoal(DateTime a, DateTime b, int sleepGoal) {
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
    return (aMinutes < bMinutes && diff < sleepGoal) ||
        (bMinutes < aMinutes && wrappedDiff < sleepGoal);
  }

// Get the start time for a date.
// TODO Performance: presorted lists? - 0x26
  DateTime? _getStartTimeForDate(DateTime date, AppState appState) {
    Meeting? firstAppointment;
    for (Meeting appointment in appState.meetings) {
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
