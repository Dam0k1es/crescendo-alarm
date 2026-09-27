// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

// docs/TODO.md T-198: the sleep-time window the Do Not Disturb trigger is
// armed for - [next alarm - Sleep Goal, next alarm). Pure computation only;
// what the native side DOES with the window (activate at its start,
// deactivate at its end, catch up a start already passed) is pinned down by
// android/app/src/test/.../SleepTimeDndPolicyTest.kt, and the real platform
// behaviour by integration_test/sleep_time_dnd_test.dart.
//
// Every fixture here is built from local wall-clock DateTimes and compared
// through millisecondsSinceEpoch, so the six-timezone CI matrix exercises
// the same frame boundary (`alarmPlatformTime`) the alarm plugin uses.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';
import 'package:crescendo_alarm/utils/utils.dart';

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

const _eightHours = TimeOfDay(hour: 8, minute: 0);

void main() {
  group('sleepTimeWindow (T-198)', () {
    test(
        'symptom 1 of T-197: the next alarm is days away -> the window starts '
        'days in the future, so nothing may happen now', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final alarm = DateTime(2026, 3, 13, 6, 30);

      final window = sleepTimeWindow(
        pendingDayValues: {_iso(alarm): alarm.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: const [],
        sleepGoal: _eightHours,
        now: now,
      );

      expect(window, isNotNull);
      expect(window!.start.isAfter(now), isTrue,
          reason: 'switching the toggle on at $now must not be inside sleep '
              'time when the only alarm is on ${alarm.toString()} - T-197 '
              'reported exactly this: DND came on immediately');
      expect(window.start.difference(now), greaterThan(const Duration(days: 2)));
    });

    test('start is the next alarm minus the Sleep Goal - WITHOUT the '
        'reminder lead time - and end is exactly the alarm', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final alarm = DateTime(2026, 3, 11, 6, 30);

      final window = sleepTimeWindow(
        pendingDayValues: {_iso(alarm): alarm.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: const [],
        sleepGoal: const TimeOfDay(hour: 7, minute: 45),
        now: now,
      )!;

      expect(window.end.millisecondsSinceEpoch,
          alarmPlatformTime(alarm).millisecondsSinceEpoch);
      expect(window.start.millisecondsSinceEpoch,
          DateTime(2026, 3, 10, 22, 45).millisecondsSinceEpoch);
    });

    test('end uses the same whole-minute boundary the alarm plugin rings at '
        '(alarmPlatformTime), not a seconds-precise planned value', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      // A planned value with seconds - the platform alarm for it is armed at
      // alarmPlatformTime(...), i.e. truncated to the minute. The window
      // must end at that ring, not 42 seconds after it.
      final planned = DateTime(2026, 3, 11, 6, 30, 42);

      final window = sleepTimeWindow(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: const [],
        sleepGoal: _eightHours,
        now: now,
      )!;

      expect(window.end.millisecondsSinceEpoch,
          DateTime(2026, 3, 11, 6, 30).millisecondsSinceEpoch);
    });

    test('inside sleep time already: the window is returned unchanged (start '
        'in the past, end ahead) - the catch-up is the native side\'s job', () {
      final now = DateTime(2026, 3, 10, 23, 0);
      final alarm = DateTime(2026, 3, 11, 6, 0);

      final window = sleepTimeWindow(
        pendingDayValues: {_iso(alarm): alarm.millisecondsSinceEpoch},
        disabledDays: const {},
        manualAlarms: const [],
        sleepGoal: _eightHours,
        now: now,
      )!;

      expect(window.start.millisecondsSinceEpoch,
          DateTime(2026, 3, 10, 22, 0).millisecondsSinceEpoch);
      expect(window.end.millisecondsSinceEpoch,
          DateTime(2026, 3, 11, 6, 0).millisecondsSinceEpoch);
    });

    test('no alarm at all -> no window', () {
      expect(
        sleepTimeWindow(
          pendingDayValues: const {},
          disabledDays: const {},
          manualAlarms: const [],
          sleepGoal: _eightHours,
          now: DateTime(2026, 3, 10, 14, 0),
        ),
        isNull,
      );
    });

    test('a Sleep Goal of 00:00 is an empty window -> no window', () {
      final alarm = DateTime(2026, 3, 11, 6, 0);
      expect(
        sleepTimeWindow(
          pendingDayValues: {_iso(alarm): alarm.millisecondsSinceEpoch},
          disabledDays: const {},
          manualAlarms: const [],
          sleepGoal: const TimeOfDay(hour: 0, minute: 0),
          now: DateTime(2026, 3, 10, 14, 0),
        ),
        isNull,
      );
    });

    group('which alarm is "the next alarm"', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final planned = DateTime(2026, 3, 11, 7, 0);

      test('a manual alarm counts by default (excludeFromSleepTime false)',
          () {
        final window = sleepTimeWindow(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          disabledDays: const {},
          manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 5, minute: 0))],
          sleepGoal: _eightHours,
          now: now,
        )!;

        expect(window.end.millisecondsSinceEpoch,
            DateTime(2026, 3, 11, 5, 0).millisecondsSinceEpoch);
      });

      test(
          'an excluded manual alarm is ignored even when it is earlier '
          '(R5: e.g. a medication reminder at night)', () {
        final window = sleepTimeWindow(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          disabledDays: const {},
          manualAlarms: [
            ManualAlarm(
                time: const TimeOfDay(hour: 3, minute: 0),
                excludeFromSleepTime: true),
          ],
          sleepGoal: _eightHours,
          now: now,
        )!;

        expect(window.end.millisecondsSinceEpoch,
            planned.millisecondsSinceEpoch);
      });

      test('a switched-off manual alarm is ignored (it does not ring)', () {
        final window = sleepTimeWindow(
          pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
          disabledDays: const {},
          manualAlarms: [
            ManualAlarm(
                time: const TimeOfDay(hour: 5, minute: 0), enabled: false),
          ],
          sleepGoal: _eightHours,
          now: now,
        )!;

        expect(window.end.millisecondsSinceEpoch,
            planned.millisecondsSinceEpoch);
      });

      test(
          'a planned day switched off in the alarm list (FR-21 disabledDays) '
          'is ignored - nothing rings then, so it cannot end sleep time', () {
        final later = DateTime(2026, 3, 12, 6, 0);
        final window = sleepTimeWindow(
          pendingDayValues: {
            _iso(planned): planned.millisecondsSinceEpoch,
            _iso(later): later.millisecondsSinceEpoch,
          },
          disabledDays: {_iso(planned)},
          manualAlarms: const [],
          sleepGoal: _eightHours,
          now: now,
        )!;

        expect(window.end.millisecondsSinceEpoch, later.millisecondsSinceEpoch);
      });

      test('only excluded manual alarms and nothing planned -> no window', () {
        expect(
          sleepTimeWindow(
            pendingDayValues: const {},
            disabledDays: const {},
            manualAlarms: [
              ManualAlarm(
                  time: const TimeOfDay(hour: 5, minute: 0),
                  excludeFromSleepTime: true),
            ],
            sleepGoal: _eightHours,
            now: now,
          ),
          isNull,
        );
      });

      test(
          'an alarm ringing right now is not "the next alarm" any more - '
          'after the first ring the window moves to the following alarm', () {
        final ringing = DateTime(2026, 3, 11, 6, 0);
        final following = DateTime(2026, 3, 12, 6, 0);
        final window = sleepTimeWindow(
          pendingDayValues: {
            _iso(ringing): ringing.millisecondsSinceEpoch,
            _iso(following): following.millisecondsSinceEpoch,
          },
          disabledDays: const {},
          manualAlarms: const [],
          sleepGoal: _eightHours,
          now: ringing,
        )!;

        expect(window.end.millisecondsSinceEpoch,
            following.millisecondsSinceEpoch);
        // Only the window moves here. Whether a next window that has
        // ALREADY begun gets entered after a ring (a backup alarm, or a
        // daytime alarm less than a Sleep Goal away) is the native side's
        // decision - SleepTimeDndPolicyTest's "A1" cases pin down that it is
        // not (independent review of 201b740).
      });

      test(
          'a planned value with seconds: once its whole-minute ring has '
          'passed, it is no longer "the next alarm" (the window must not end '
          'in the past and so clear itself)', () {
        final planned = DateTime(2026, 3, 11, 6, 30, 42);
        final following = DateTime(2026, 3, 12, 6, 30);
        final window = sleepTimeWindow(
          pendingDayValues: {
            _iso(planned): planned.millisecondsSinceEpoch,
            _iso(following): following.millisecondsSinceEpoch,
          },
          disabledDays: const {},
          manualAlarms: const [],
          sleepGoal: _eightHours,
          // Rang at 06:30:00, the planned value itself is still 22 s ahead.
          now: DateTime(2026, 3, 11, 6, 30, 20),
        )!;

        expect(window.end.millisecondsSinceEpoch,
            following.millisecondsSinceEpoch);
      });
    });
  });
}
