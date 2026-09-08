import 'scheduling.dart';

int sleepGoalInt = 8;
Duration sleepGoal = const Duration(hours: 8);
Duration wakeUpOffset = const Duration(hours: 2);

List<DateTime> adjustTime(List<DateTime> alarmTimes) {
  int numberOfAdjustedAlarms = 0;
  DateTime newAlarmTime = alarmTimes[0];
  DateTime earliestAlarm =
      getEarliestEvent(List.from(alarmTimes), sleepGoalInt);
  DateTime referenceAlarm = earliestAlarm;
  DateTime offset = earliestAlarm.add(wakeUpOffset);
  List<DateTime> adjustedAlarmTimes = [];

  // Iterate through the alarm times and adjust the alarm times (upwards)
  for (DateTime alarmTime in alarmTimes) {
    if (alarmTime.hour - offset.hour > 0) {
      numberOfAdjustedAlarms += 1;
      if (alarmTime.isAfter(earliestAlarm)) {
        // Set the alarm time $wakeUpOffset later for every day, as long as it is not earlier than the latest possible alarm time
        if (isBeforeTime(newAlarmTime.add(wakeUpOffset), alarmTime) ||
            isAtSameMomentAsTime(newAlarmTime.add(wakeUpOffset), alarmTime)) {
          referenceAlarm = newAlarmTime.add(wakeUpOffset);
        }
        newAlarmTime = DateTime(alarmTime.year, alarmTime.month, alarmTime.day,
            referenceAlarm.hour, referenceAlarm.minute, referenceAlarm.second);
      } else if (alarmTime.isBefore(earliestAlarm)) {
        // Set the alarm time $wakeUpOffset earlier for every day, as long as it is later than the latest possible alarm time
        if (isAfterTime(newAlarmTime.subtract(wakeUpOffset), earliestAlarm) ||
            isAtSameMomentAsTime(
                newAlarmTime.subtract(wakeUpOffset), earliestAlarm)) {
          referenceAlarm = newAlarmTime.subtract(wakeUpOffset);
        }
        newAlarmTime = DateTime(alarmTime.year, alarmTime.month, alarmTime.day,
            referenceAlarm.hour, referenceAlarm.minute, referenceAlarm.second);
      }
    } else {
      newAlarmTime = alarmTime;
    }
    adjustedAlarmTimes.add(newAlarmTime);
  }

  // Iterate through the alarm times and adjust the alarm times (downwards)
  // List<DateTime> reversedAlarmTimes = newAlarmTime.reversed.toList();

  if (numberOfAdjustedAlarms >= 7) {
    return [];
  } else {
    return adjustedAlarmTimes;
  }
}

bool isBeforeTime(DateTime a, DateTime b) {
  if (a.hour < b.hour) {
    return true;
  } else if (a.hour == b.hour) {
    return a.minute < b.minute;
  }
  return false;
}

bool isAfterTime(DateTime a, DateTime b) {
  if (a.hour > b.hour) {
    return true;
  } else if (a.hour == b.hour) {
    return a.minute > b.minute;
  }
  return false;
}

bool isAtSameMomentAsTime(DateTime a, DateTime b) {
  return a.hour == b.hour && a.minute == b.minute;
}
