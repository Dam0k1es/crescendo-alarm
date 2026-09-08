// This is a standalone interactive debug script, not an automated test -
// print is its actual output mechanism, not a logging omission.
// ignore_for_file: avoid_print
import 'adjust.dart';
import 'cases.dart';
import 'package:intl/intl.dart';
import 'dart:io';

void main() {
  // Read the shift schedules from cases.dart
  List<List<DateTime>> originalSchedules = schedules;

  // Print the original and adjusted schedules side by side
  for (int i = 0; i < originalSchedules.length; i++) {
    print('Schedule ${i + 1}:');
    print('Original: ${formatSchedule(originalSchedules[i])}');
    print('Adjusted: ${formatSchedule(adjustTime(originalSchedules[i]))}');
    print('----------------------------------------');
    stdin.readLineSync();
  }
}

String formatSchedule(List<DateTime> schedule) {
  List<String> formattedDates = [];
  for (DateTime dt in schedule) {
    formattedDates.add(DateFormat('EEE dd.MM.yyyy HH:mm').format(dt));
  }
  return formattedDates.join(', ');
}
