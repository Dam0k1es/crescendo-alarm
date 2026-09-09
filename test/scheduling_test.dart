import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling.dart';
// Meeting is declared in meeting_data.dart, but that file is `part of`
// screen_schedule.dart rather than an independent library - import the
// screen instead to reach it (scheduling.dart itself does the same).
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Real tests for the production scheduling functions - previously these had
// no automated coverage at all. The getEarliestEvent cases below are ported
// from the old test/getEarliestAlarm/ scripts (never run by `flutter test`),
// corrected for the unit mismatch that script had: production's sleepGoal
// parameter is already in minutes (see scheduling.dart's
// `sleepGoal = timeOfDay.hour * 60 + timeOfDay.minute`), while the old
// script took whole hours and multiplied by 60 internally. Passing the same
// scenarios with sleepGoal pre-converted to minutes (hours * 60) exercises
// the identical comparison and expects the identical results.
Meeting _meetingAt(DateTime from, {bool isAllDay = false, String name = ''}) {
  return Meeting(
    from: from,
    to: from.add(const Duration(hours: 1)),
    isAllDay: isAllDay,
    eventName: name,
    startTimeZone: 'Etc/UTC',
    endTimeZone: 'Etc/UTC',
  );
}

void main() {
  group('getEarliestEvent (ported from test/getEarliestAlarm)', () {
    const eightHoursInMinutes = 8 * 60;

    final cases = <String, ({DateTime expected, List<DateTime> week, int sleepGoalMinutes})>{
      'normal day time': (
        expected: DateTime(2020, 6, 29, 12, 0),
        week: [
          DateTime(2020, 6, 29, 12, 0),
          DateTime(2020, 6, 30, 13, 0),
          DateTime(2020, 7, 1, 14, 0),
          DateTime(2020, 7, 2, 15, 0),
          DateTime(2020, 7, 3, 12, 30),
          DateTime(2020, 7, 4, 14, 30),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'crosses day boundary': (
        expected: DateTime(2021, 6, 30, 23, 0),
        week: [
          DateTime(2021, 6, 29, 1, 0),
          DateTime(2021, 6, 30, 23, 0),
          DateTime(2021, 7, 1, 14, 0),
          DateTime(2021, 7, 2, 15, 0),
          DateTime(2021, 7, 3, 12, 30),
          DateTime(2021, 7, 4, 14, 30),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'near day boundary': (
        expected: DateTime(2022, 7, 1, 0, 0), // DateTime(...,30,24,0) normalizes to July 1st, 00:00
        week: [
          DateTime(2022, 6, 29, 1, 0),
          DateTime(2022, 6, 30, 24, 0),
          DateTime(2022, 7, 1, 2, 0),
          DateTime(2022, 7, 2, 3, 0),
          DateTime(2022, 7, 3, 12, 30),
          DateTime(2022, 7, 4, 14, 30),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'far before day boundary, one value out of sleep goal expected': (
        expected: DateTime(2023, 6, 30, 20, 0),
        week: [
          DateTime(2023, 6, 29, 1, 0),
          DateTime(2023, 6, 30, 20, 0),
          DateTime(2023, 7, 1, 21, 0),
          DateTime(2023, 7, 2, 22, 0),
          DateTime(2023, 7, 3, 23, 30),
          DateTime(2023, 7, 4, 14, 30),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'shortly after day boundary, rest at usual wake-up times': (
        expected: DateTime(2024, 6, 29, 1, 0),
        week: [
          DateTime(2024, 6, 29, 1, 0),
          DateTime(2024, 6, 30, 6, 0),
          DateTime(2024, 7, 1, 6, 30),
          DateTime(2024, 7, 2, 7, 0),
          DateTime(2024, 7, 3, 6, 15),
          DateTime(2024, 7, 4, 8, 30),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'late night alarms, early hours': (
        expected: DateTime(2025, 6, 29, 0, 0),
        week: [
          DateTime(2025, 6, 29, 0, 0),
          DateTime(2025, 6, 30, 2, 0),
          DateTime(2025, 7, 1, 4, 0),
          DateTime(2025, 7, 2, 6, 0),
          DateTime(2025, 7, 3, 8, 0),
          DateTime(2025, 7, 4, 10, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'weekend alarms, varying sleep goals': (
        expected: DateTime(2026, 7, 1, 8, 0),
        week: [
          DateTime(2026, 6, 29, 12, 0),
          DateTime(2026, 7, 1, 8, 0),
          DateTime(2026, 7, 2, 9, 0),
          DateTime(2026, 7, 3, 10, 0),
          DateTime(2026, 7, 4, 11, 0),
          DateTime(2026, 7, 5, 12, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'alarms during holidays': (
        expected: DateTime(2027, 12, 25, 8, 0),
        week: [
          DateTime(2027, 12, 24, 22, 0),
          DateTime(2027, 12, 25, 8, 0),
          DateTime(2027, 12, 26, 9, 0),
          DateTime(2027, 12, 27, 10, 0),
          DateTime(2027, 12, 28, 11, 0),
          DateTime(2027, 12, 29, 12, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'alarms during special events': (
        expected: DateTime(2028, 2, 14, 7, 0),
        week: [
          DateTime(2028, 2, 13, 18, 0),
          DateTime(2028, 2, 14, 7, 0),
          DateTime(2028, 2, 15, 8, 0),
          DateTime(2028, 2, 16, 9, 0),
          DateTime(2028, 2, 17, 10, 0),
          DateTime(2028, 2, 18, 11, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'alarms during vacation': (
        expected: DateTime(2029, 8, 1, 6, 0),
        week: [
          DateTime(2029, 7, 31, 22, 0),
          DateTime(2029, 8, 1, 6, 0),
          DateTime(2029, 8, 2, 7, 0),
          DateTime(2029, 8, 3, 8, 0),
          DateTime(2029, 8, 4, 9, 0),
          DateTime(2029, 8, 5, 10, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'consecutive early mornings': (
        expected: DateTime(2030, 6, 29, 2, 0),
        week: [
          DateTime(2030, 6, 29, 2, 0),
          DateTime(2030, 6, 30, 3, 0),
          DateTime(2030, 7, 1, 4, 0),
          DateTime(2030, 7, 2, 5, 0),
          DateTime(2030, 7, 3, 6, 0),
          DateTime(2030, 7, 4, 7, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'weekend alarms, various times': (
        expected: DateTime(2031, 6, 29, 8, 0),
        week: [
          DateTime(2031, 6, 29, 8, 0),
          DateTime(2031, 7, 1, 12, 0),
          DateTime(2031, 7, 2, 9, 0),
          DateTime(2031, 7, 3, 10, 0),
          DateTime(2031, 7, 4, 11, 0),
          DateTime(2031, 7, 5, 8, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'early morning alarms, weekday': (
        expected: DateTime(2032, 6, 29, 4, 0),
        week: [
          DateTime(2032, 6, 29, 4, 0),
          DateTime(2032, 6, 30, 5, 0),
          DateTime(2032, 7, 1, 6, 0),
          DateTime(2032, 7, 2, 7, 0),
          DateTime(2032, 7, 3, 8, 0),
          DateTime(2032, 7, 4, 9, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'long weekend': (
        expected: DateTime(2033, 6, 29, 8, 0),
        week: [
          DateTime(2033, 6, 29, 8, 0),
          DateTime(2033, 7, 1, 10, 0),
          DateTime(2033, 7, 2, 9, 0),
          DateTime(2033, 7, 3, 11, 0),
          DateTime(2033, 7, 4, 12, 0),
          DateTime(2033, 7, 5, 8, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'short holiday': (
        expected: DateTime(2034, 12, 25, 9, 0),
        week: [
          DateTime(2034, 12, 25, 9, 0),
          DateTime(2034, 12, 26, 10, 0),
          DateTime(2034, 12, 27, 11, 0),
          DateTime(2034, 12, 28, 12, 0),
          DateTime(2034, 12, 29, 13, 0),
          DateTime(2034, 12, 30, 14, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'special event, ascending times': (
        expected: DateTime(2035, 2, 14, 8, 0),
        week: [
          DateTime(2035, 2, 14, 8, 0),
          DateTime(2035, 2, 15, 9, 0),
          DateTime(2035, 2, 16, 10, 0),
          DateTime(2035, 2, 17, 11, 0),
          DateTime(2035, 2, 18, 12, 0),
          DateTime(2035, 2, 19, 13, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
      'summer vacation, ascending times': (
        expected: DateTime(2036, 8, 1, 7, 0),
        week: [
          DateTime(2036, 8, 1, 7, 0),
          DateTime(2036, 8, 2, 8, 0),
          DateTime(2036, 8, 3, 9, 0),
          DateTime(2036, 8, 4, 10, 0),
          DateTime(2036, 8, 5, 11, 0),
          DateTime(2036, 8, 6, 12, 0),
        ],
        sleepGoalMinutes: eightHoursInMinutes,
      ),
    };

    cases.forEach((description, c) {
      test(description, () {
        expect(getEarliestEvent(List.from(c.week), c.sleepGoalMinutes), c.expected);
      });
    });
  });

  group('getStartTimeForDate', () {
    final day = DateTime(2026, 3, 10);

    test('no meeting on that day returns null', () {
      final meetings = [_meetingAt(DateTime(2026, 3, 9, 9, 0))];
      expect(getStartTimeForDate(day, meetings), isNull);
    });

    test('a single same-day meeting returns its start time', () {
      final expected = DateTime(2026, 3, 10, 9, 30);
      final meetings = [_meetingAt(expected)];
      expect(getStartTimeForDate(day, meetings), expected);
    });

    test('the earliest of several same-day meetings is returned', () {
      final earliest = DateTime(2026, 3, 10, 7, 0);
      final meetings = [
        _meetingAt(DateTime(2026, 3, 10, 12, 0)),
        _meetingAt(earliest),
        _meetingAt(DateTime(2026, 3, 10, 9, 0)),
      ];
      expect(getStartTimeForDate(day, meetings), earliest);
    });

    test('an all-day meeting on that day is ignored', () {
      final meetings = [
        _meetingAt(DateTime(2026, 3, 10, 0, 0), isAllDay: true),
      ];
      expect(getStartTimeForDate(day, meetings), isNull);
    });

    test('an all-day meeting does not hide a real same-day meeting', () {
      final expected = DateTime(2026, 3, 10, 8, 0);
      final meetings = [
        _meetingAt(DateTime(2026, 3, 10, 0, 0), isAllDay: true),
        _meetingAt(expected),
      ];
      expect(getStartTimeForDate(day, meetings), expected);
    });
  });

  group('adjustAlarmTimes', () {
    test('a time within the offset window is left unchanged', () {
      final earliestAlarm = DateTime(2026, 3, 10, 7, 0);
      const offset = Duration(minutes: 30);
      final alarmTimes = [DateTime(2026, 3, 10, 7, 15)];

      final result = adjustAlarmTimes(alarmTimes, earliestAlarm, offset);

      expect(result, [DateTime(2026, 3, 10, 7, 15)]);
    });

    test('a time on a later date is estimated from the earliest alarm, even '
        'if its own time-of-day would have been within the window - this is '
        'the known scheduling gap tracked as docs/TODO.md T-02, pinned down '
        'here rather than silently changed', () {
      final earliestAlarm = DateTime(2026, 3, 10, 7, 0);
      const offset = Duration(minutes: 30);
      // 2026-03-11 07:10 is only 10 minutes past 07:00-of-day, well inside a
      // 30-minute window - but because the comparison is against the
      // absolute DateTime 2026-03-10 07:30, any later calendar date counts
      // as "after" it regardless of time-of-day.
      final alarmTimes = [DateTime(2026, 3, 11, 7, 10)];

      final result = adjustAlarmTimes(alarmTimes, earliestAlarm, offset);

      expect(result, [DateTime(2026, 3, 11, 7, 30)]);
    });

    test('7 or more estimated alarms abort scheduling entirely', () {
      final earliestAlarm = DateTime(2026, 3, 10, 7, 0);
      const offset = Duration(minutes: 30);
      final alarmTimes = List.generate(
        7,
        (i) => DateTime(2026, 3, 10 + i, 20, 0), // all clearly after the offset
      );

      expect(adjustAlarmTimes(alarmTimes, earliestAlarm, offset), isNull);
    });

    test('6 estimated alarms still schedule normally', () {
      final earliestAlarm = DateTime(2026, 3, 10, 7, 0);
      const offset = Duration(minutes: 30);
      final alarmTimes = List.generate(
        6,
        (i) => DateTime(2026, 3, 10 + i, 20, 0),
      );

      expect(adjustAlarmTimes(alarmTimes, earliestAlarm, offset), isNotNull);
    });
  });
}
