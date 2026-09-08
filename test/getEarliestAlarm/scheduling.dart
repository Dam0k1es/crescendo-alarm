DateTime getEarliestEvent(List<DateTime> alarmTimes, int sleepGoal) {

  alarmTimes.sort((a, b) {
  // year, month
    int aMinutes = a.hour * 60 + a.minute;
    int bMinutes = b.hour * 60 + b.minute;

    return aMinutes.compareTo(bMinutes);
  });
      
  DateTime earliest = alarmTimes.first;

  for (var time in alarmTimes) {
    if (isEarlierConsideringSleepGoal(time, earliest, sleepGoal)) {
      earliest = time;
    }
  }

  return earliest;
}

bool isEarlierConsideringSleepGoal(DateTime a, DateTime b, int sleepGoal) {
  // Calculate the total minutes of the day for both times
  int aMinutes = a.hour * 60 + a.minute;
  int bMinutes = b.hour * 60 + b.minute;

  // Calculate the absolute difference in minutes between a and b
  int diff = (bMinutes - aMinutes).abs();

  // Calculate the maximum allowed difference based on sleepGoal
  int maxAllowedDiff = sleepGoal * 60;

  // Calculate the difference if considering wrapping around the day
  int wrappedDiff = (24 * 60 - aMinutes + bMinutes).abs();

  // Check if a is earlier than b considering the sleepGoal
  // The condition is either:
  // 1. a is earlier than b and the difference is within the sleepGoal range
  // 2. b is earlier than a and the wrapped difference is within the sleepGoal range
  return (aMinutes < bMinutes && diff < maxAllowedDiff) ||
         (bMinutes < aMinutes && wrappedDiff < maxAllowedDiff);
}
