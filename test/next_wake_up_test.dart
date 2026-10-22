import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/next_wake_up.dart';

// docs/TODO.md T-66: replacement for Scheduler.nextAlarmTime(), which
// scheduleSleepReminder() (FR-16 checkpoint 2) depends on - Phase 6 would
// delete the old Scheduler class. The replacement must consider BOTH
// sources: scheduling-v2's planned daily values AND manual alarms. The
// latter is not an FR-15 violation: FR-15 forbids the *planning logic* from
// touching ManualAlarms - a bedtime reminder is allowed to read them,
// otherwise it would plan into a void for users who only set manual alarms.

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

void main() {
  group('nextWakeUpTime (T-66)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('only planned v2 values -> the earliest future one', () {
      final soon = DateTime(2026, 3, 11, 7, 0);
      final later = DateTime(2026, 3, 12, 6, 30);

      final result = nextWakeUpTime(
        pendingDayValues: {
          _iso(soon): soon.millisecondsSinceEpoch,
          _iso(later): later.millisecondsSinceEpoch,
        },
        disabledDays: const {},
        manualAlarms: const [],
        now: now,
      );

      expect(result, soon);
    });

    test('past and null values are ignored', () {
      final past = DateTime(2026, 3, 9, 7, 0);
      final future = DateTime(2026, 3, 11, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {
          _iso(past): past.millisecondsSinceEpoch,
          '2026-03-10': null,
          _iso(future): future.millisecondsSinceEpoch,
        },
        disabledDays: const {},
        manualAlarms: const [],
        now: now,
      );

      expect(result, future);
    });

    test('only a ManualAlarm, time still ahead today -> today', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        disabledDays: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 8, minute: 15))],
        now: now, // 06:00
      );

      expect(result, DateTime(2026, 3, 10, 8, 15));
    });

    test('only a ManualAlarm, time already past today -> tomorrow', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        disabledDays: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 5, minute: 0))],
        now: now, // 06:00
      );

      expect(result, DateTime(2026, 3, 11, 5, 0));
    });

    test('both sources, planned value is earlier -> planned value', () {
      final planned = DateTime(2026, 3, 10, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 9, minute: 0))],
        now: now,
      );

      expect(result, planned);
    });

    test('both sources, ManualAlarm is earlier -> ManualAlarm wins', () {
      final planned = DateTime(2026, 3, 11, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 6, minute: 30))],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 6, 30));
    });

    test('several ManualAlarms -> the earliest counts', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        disabledDays: const {},
        manualAlarms: [
          ManualAlarm(time: const TimeOfDay(hour: 9, minute: 0)),
          ManualAlarm(time: const TimeOfDay(hour: 7, minute: 45)),
        ],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 7, 45));
    });

    test('no source yields anything -> null', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {'2026-03-11': null},
        disabledDays: const {},
        manualAlarms: const [],
        now: now,
      );

      expect(result, isNull);
    });

    // docs/TODO.md T-14: since `repeatOnDays` is now honoured when actually
    // arming a manual alarm (manual_alarm_repeat_test.dart), this function
    // has to agree - otherwise the bedtime reminder could send the user to
    // bed for a "tomorrow" wake-up that repeatOnDays says will not ring.
    test('a manual alarm repeating only on a later weekday is not treated '
        'as tomorrow', () {
      // 2026-03-10 is a Tuesday; the alarm only repeats on Friday.
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        repeatOnDays: {
          for (final day in DayOfWeek.values) day: day == DayOfWeek.friday,
        },
      );

      final result = nextWakeUpTime(
        pendingDayValues: const {},
        disabledDays: const {},
        manualAlarms: [alarm],
        now: now,
      );

      expect(result, DateTime(2026, 3, 13, 7, 0),
          reason: '2026-03-13 is the next Friday, not "tomorrow"');
    });
  });
  // docs/TODO.md T-239 (audit G6-01): the alarm plugin rings at the floored
  // whole minute (`alarmPlatformTime`), but a planned value can carry seconds
  // (a daily shift of 33 min 20 s). Compared raw, an alarm that has rung at
  // 06:33:00 stayed "next" until 06:33:20, so every mirror/reminder write in
  // those seconds - and the cold-start refresh and the ring checkpoint both
  // run in them - pointed at the alarm that had just rung.
  group('nextWakeUpTime reads a planned value at its ring minute (T-239)', () {
    final planned = DateTime(2026, 3, 11, 6, 33, 20);
    final key = _iso(planned);
    final values = {key: planned.millisecondsSinceEpoch};

    test('inside the seconds after the ring minute the alarm is no longer next',
        () {
      final result = nextWakeUpTime(
        pendingDayValues: values,
        disabledDays: const {},
        manualAlarms: const [],
        now: DateTime(2026, 3, 11, 6, 33, 5),
      );

      expect(result, isNull, reason: 'it rang at 06:33:00');
    });

    test('before the ring minute the value is returned as that minute', () {
      final result = nextWakeUpTime(
        pendingDayValues: values,
        disabledDays: const {},
        manualAlarms: const [],
        now: DateTime(2026, 3, 11, 6, 32, 0),
      );

      expect(result, DateTime(2026, 3, 11, 6, 33, 0));
    });

    test('counter-test: one second before the ring minute it is still next',
        () {
      final result = nextWakeUpTime(
        pendingDayValues: values,
        disabledDays: const {},
        manualAlarms: const [],
        now: DateTime(2026, 3, 11, 6, 32, 59),
      );

      expect(result, DateTime(2026, 3, 11, 6, 33, 0));
    });

    test('the next day\'s alarm wins once the first one has rung', () {
      final nextDay = DateTime(2026, 3, 12, 6, 0);
      final result = nextWakeUpTime(
        pendingDayValues: {
          ...values,
          _iso(nextDay): nextDay.millisecondsSinceEpoch,
        },
        disabledDays: const {},
        manualAlarms: const [],
        now: DateTime(2026, 3, 11, 6, 33, 5),
      );

      expect(result, nextDay);
    });
  });
}
