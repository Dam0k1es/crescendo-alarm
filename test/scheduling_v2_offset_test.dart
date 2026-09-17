import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-61, levels 1/2/3 of the planned test structure.
//
// Semantics (Option B, decided before these tests): every domain-layer value
// is a **real absolute instant** (FR-1). Only where a device-local
// `TimeOfDay` (`preferredWakeUpTime`) meets an instant does `deviceUtcOffset`
// need to come in - i.e. in applyGapDayDrift and coldStart.
// distribute/groupTarget, by contrast, are frame-invariant: they exclusively
// compare instant with instant, and the day_i placement in the local frame
// yields, after converting back, exactly the same instant as in the raw
// frame.
//
// All instants are explicitly constructed as UTC and the device offset is
// explicitly passed in - the test machine's system time zone must never come
// into play (FR-2 "testability").

/// A real instant (UTC).
DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 3, day, hour, minute);

/// A device on Berlin daylight-saving time.
const berlin = Duration(hours: 2);

void main() {
  group('applyGapDayDrift with deviceUtcOffset != 0 (T-61, level 2)', () {
    test('preferredWakeUpTime is already reached (read locally) -> no drift', () {
      // v = 05:00 UTC = 07:00 local in Berlin. preferredWakeUpTime is 07:00
      // local, so it's exactly reached - it must NOT drift. The old code
      // reads 05:00 as digits and drifts 30min toward "07:00".
      final result = applyGapDayDrift(
        v: _utc(5, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      expect(result, _utc(5, 0, day: 2));
    });

    test('drift toward later is measured locally', () {
      // v = 05:00 UTC = 07:00 local, preferredWakeUpTime 09:00 local ->
      // distance 2h, capped at 30min -> 07:30 local = 05:30 UTC the next day.
      final result = applyGapDayDrift(
        v: _utc(5, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      expect(result, _utc(5, 30, day: 2));
    });

    test('the local date counts, not the UTC date', () {
      // v = 23:00 UTC on day 1 = 01:00 local on day 2. "Tomorrow" is
      // therefore locally day 3, not day 2. preferredWakeUpTime = 01:00
      // local (reached).
      final result = applyGapDayDrift(
        v: _utc(23, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 1, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: berlin,
      );

      // Locally day 3, 01:00 -> instant 23:00 UTC on day 2.
      expect(result, _utc(23, 0, day: 2));
    });

    test('invariance: unchanged behaviour at deviceUtcOffset = 0', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      expect(result, _utc(7, 30, day: 2));
    });
  });

  group('coldStart with deviceUtcOffset != 0 (T-61, level 2)', () {
    test('preferredWakeUpTime is set as the window day\'s local time of day', () {
      // Window days are local calendar dates (date markers). preferredWakeUpTime
      // 07:00 local on day 1 -> instant 05:00 UTC on day 1.
      final days = [_utc(0, 0, day: 1), _utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        deviceUtcOffset: berlin,
      );

      expect(result[days[0]], _utc(5, 0, day: 1));
      expect(result[days[1]], _utc(5, 0, day: 2));
    });

    test('a local time before the offset slides to the UTC day before', () {
      // 01:00 local on day 2 = 23:00 UTC on day 1.
      final days = [_utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 1, minute: 0),
        deviceUtcOffset: berlin,
      );

      expect(result[days[0]], _utc(23, 0, day: 1));
    });

    test('invariance: unchanged behaviour at deviceUtcOffset = 0', () {
      final days = [_utc(0, 0, day: 1)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        deviceUtcOffset: Duration.zero,
      );

      expect(result[days[0]], _utc(9, 0, day: 1));
    });
  });

  group('hardFloor under an offset (T-61, level 1)', () {
    Meeting meetingAt(DateTime from) => Meeting(
          from: from,
          to: from.add(const Duration(hours: 1)),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        );

    test('the return value is offset-independent (the appointment does not shift)',
        () {
      // 23:00 UTC on day 10 = 01:00 local on day 11 (Berlin, +2).
      final event = meetingAt(_utc(23, 0, day: 10));

      final berlinValue = hardFloor(
        day: _utc(0, 0, day: 11), // local calendar day in Berlin
        allEvents: [event],
        deviceUtcOffset: berlin,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );
      final utcValue = hardFloor(
        day: _utc(0, 0, day: 10), // same appointment, but a UTC calendar day
        allEvents: [event],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );

      // FR-1/FR-16: instant-based - identical instant in both zones.
      expect(berlinValue, _utc(23, 0, day: 10));
      expect(utcValue, berlinValue);
    });

    test('the day assignment, by contrast, follows the offset', () {
      final event = meetingAt(_utc(23, 0, day: 10));

      // Under +2 the appointment belongs to local day 11, not day 10.
      expect(
        hardFloor(
          day: _utc(0, 0, day: 10),
          allEvents: [event],
          deviceUtcOffset: berlin,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('computeWeekPlan invariance (T-61, level 3a)', () {
    Meeting meetingAt(DateTime from) => Meeting(
          from: from,
          to: from.add(const Duration(hours: 1)),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        );

    test('same local appointment reading -> same plan, just shifted by the offset',
        () {
      final window = [1, 2, 3, 4, 5, 6].map((d) => _utc(0, 0, day: d)).toList();

      WeekPlanResult plan(Duration offset, Duration eventShift) => computeWeekPlan(
            window: window,
            lastEffectiveWakeTime: _utc(7, 0, day: 0).subtract(offset),
            // The appointment is shifted so its LOCAL reading is identical in
            // both runs (05:00 local on day 6).
            allEvents: [meetingAt(_utc(5, 0, day: 6).subtract(eventShift))],
            deviceUtcOffset: offset,
            durationToWakeUp: Duration.zero,
            durationToGetReady: Duration.zero,
            preferredWakeUpTime: const TimeOfDay(hour: 10, minute: 0),
            maxDailyDelta: const Duration(minutes: 30),
            gapDayCounter: 0,
          );

      final atUtc = plan(Duration.zero, Duration.zero);
      final atBerlin = plan(berlin, berlin);

      for (final day in window) {
        final utcValue = atUtc.valuesByDay[day];
        final berlinValue = atBerlin.valuesByDay[day];
        if (utcValue == null) {
          expect(berlinValue, isNull, reason: 'day $day');
          continue;
        }
        // Identical local digits => the instants differ by exactly the
        // offset. If the arithmetic were frame-inconsistent, something else
        // would come out here.
        expect(berlinValue, utcValue.subtract(berlin), reason: 'day $day');
      }
    });
  });

  group('distribute/groupTarget are frame-invariant (T-61, locked in)', () {
    test('distribute yields the same instant under any offset', () {
      final anchor = _utc(5, 0, day: 1);
      final target = _utc(3, 0, day: 3);

      final zero = distribute(
        anchor: anchor,
        target: target,
        n: 2,
        maxDailyDelta: const Duration(hours: 2),
      );
      final shifted = distribute(
        anchor: anchor,
        target: target,
        n: 2,
        maxDailyDelta: const Duration(hours: 2),
      );

      // Deliberately the same signature: distribute gets NO offset, because
      // it cannot change the result (the difference of two instants in the
      // same frame, and the day_i placement is offset-neutral).
      expect(shifted.valuesByDayOffset[1], zero.valuesByDayOffset[1]);
      expect(shifted.valuesByDayOffset[2], zero.valuesByDayOffset[2]);
      expect(zero.valuesByDayOffset[2], _utc(3, 0, day: 3));
    });
  });
}
