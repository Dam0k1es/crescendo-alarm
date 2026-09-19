import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// Phase 1 (docs/scheduling-v2-spec.md, "Implementation order"): the pure
// segment/distribution core - distribute (FR-6), applyGapDayDrift (FR-4),
// hardFloor/eventsForDay (FR-2), groupTarget (FR-5), planGapOrRunStartDay (FR-7).
// Every test case here is taken verbatim (same numbers) from the "Test:" bullets
// under the matching FR in the spec.

DateTime _t(int hour, int minute, {int day = 1}) =>
    DateTime(2026, 1, day, hour, minute);

// FR-2 tests construct events directly in UTC and pass the device offset
// explicitly, so they're deterministic regardless of the host machine's own
// configured timezone (see spec, FR-2 "Testability").
DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 1, day, hour, minute);

Meeting _meetingAt(DateTime from, {bool isAllDay = false}) {
  return Meeting(
    from: from,
    to: from.add(const Duration(hours: 1)),
    isAllDay: isAllDay,
    startTimeZone: 'Etc/UTC',
    endTimeZone: 'Etc/UTC',
  );
}

void main() {
  group('distribute (FR-6)', () {
    test('normal case, direction "earlier"', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 5,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isFalse);
      // Tag_i lands on anchor.day + i (a genuine calendar-date advance per
      // day) - only the wall-clock reading is interpolated; ΔT itself is
      // wall-clock-only (FR-6/FR-1, see distribute()'s doc comment).
      expect(result.valuesByDayOffset[1], _t(7, 18, day: 2));
      expect(result.valuesByDayOffset[2], _t(6, 36, day: 3));
      expect(result.valuesByDayOffset[3], _t(5, 54, day: 4));
      expect(result.valuesByDayOffset[4], _t(5, 12, day: 5));
      expect(result.valuesByDayOffset[5], _t(4, 30, day: 6));
    });

    test('normal case, direction "later"', () {
      final result = distribute(
        anchor: _t(6, 0),
        target: _t(9, 0),
        n: 3,
        maxDailyDelta: const Duration(minutes: 90),
      );

      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.valuesByDayOffset[1], _t(7, 0, day: 2));
      expect(result.valuesByDayOffset[2], _t(8, 0, day: 3));
      expect(result.valuesByDayOffset[3], _t(9, 0, day: 4));
    });

    test('forced overrun, N>1 - distributed over all days, not dumped', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 3,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1], _t(6, 50, day: 2));
      expect(result.valuesByDayOffset[2], _t(5, 40, day: 3));
      expect(result.valuesByDayOffset[3], _t(4, 30, day: 4));
    });

    test('forced overrun, N=1 - a full jump is not a spec defect', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(2, 0),
        n: 1,
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1], _t(2, 0, day: 2));
    });
  });

  group('applyGapDayDrift (FR-4, isolated from FR-7\'s cap)', () {
    // The result always lies on v.day + 1 (the real, actually planned
    // "today") - exactly like distribute()'s day_i placement, see
    // applyGapDayDrift()'s doc comment. Values are explicit UTC instants and
    // the device offset is explicitly 0 (T-61/Option B) - behaviour at a
    // non-zero offset is covered by test/scheduling_v2_offset_test.dart.
    test('no preferredWakeUpTime -> holds (time of day unchanged, date +1)',
        () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 0, day: 2));
    });

    test('drift toward later, full step', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 30, day: 2));
    });

    test('drift toward earlier, full step', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 5, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(6, 30, day: 2));
    });

    test('target closer than maxDailyDelta -> no overshoot', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 15),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 15, day: 2));
    });

    test(
        'preferredWakeUpTime already reached -> time of day unchanged, date +1',
        () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );
      expect(result, _utc(7, 0, day: 2));
    });
  });

  group('hardFloor / eventsForDay (FR-2)', () {
    test('several appointments - the earlier one counts', () {
      final events = [
        _meetingAt(_utc(9, 0)),
        _meetingAt(_utc(7, 0)),
      ];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, _utc(6, 30));
    });

    test('an all-day appointment never enters', () {
      final events = [
        _meetingAt(_utc(12, 0), isAllDay: true),
        _meetingAt(_utc(8, 0)),
      ];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, _utc(7, 30));
    });

    test('only an all-day appointment -> gap day, no hardFloor', () {
      final events = [_meetingAt(_utc(12, 0), isAllDay: true)];

      final result = hardFloor(
        day: _utc(0, 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 15),
        durationToGetReady: const Duration(minutes: 15),
      );

      expect(result, isNull);
    });

    test(
        'appointment\'s own time zone: day assignment follows the device time zone',
        () {
      // Tom, device on Europe/Berlin (CET, +1h). Appointment
      // startTimeZone=Asia/Tokyo, start 03:00 JST on "day 2" = already
      // correctly converted to 18:00 UTC the day before ("day 1") - this
      // conversion is existing, unchanged functionality and is already given
      // here as `from`, not part of the test.
      final tokyoMeeting = _meetingAt(_utc(18, 0, day: 1));

      final berlinOffset = const Duration(hours: 1);

      final onDayBefore = eventsForDay(
        _utc(0, 0, day: 1),
        allEvents: [tokyoMeeting],
        deviceUtcOffset: berlinOffset,
      );
      expect(onDayBefore, [tokyoMeeting]);

      final onTokyoDate = eventsForDay(
        _utc(0, 0, day: 2),
        allEvents: [tokyoMeeting],
        deviceUtcOffset: berlinOffset,
      );
      expect(onTokyoDate, isEmpty);
    });
  });

  group('groupTarget (FR-5)', () {
    // The curve's shape does not depend on maxDailyDelta (only the overrun
    // notification in distribute() does) - any value is fine here.
    const maxDailyDelta = Duration(minutes: 60);

    // HardFloorPoint.value must lie on the real calendar date its dayOffset
    // claims (anchor.day + dayOffset) - exactly as computeWeekPlan actually
    // constructs it later; distribute()/groupTarget compare real dates, not
    // just times of day (see distribute()'s date advancement).
    test('simple case - t1, t2 same direction, no violation', () {
      final t1 = HardFloorPoint(dayOffset: 2, value: _t(7, 0, day: 3));
      final t2 = HardFloorPoint(dayOffset: 4, value: _t(6, 0, day: 5));

      final result = groupTarget(
        anchor: _t(8, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t2);
    });

    test('an intermediate point would be violated - the run must shrink', () {
      final t1 = HardFloorPoint(
          dayOffset: 3, value: _t(6, 0, day: 4)); // Wednesday, strict
      final t2 = HardFloorPoint(
          dayOffset: 5, value: _t(8, 0, day: 6)); // Friday, looser

      final result = groupTarget(
        anchor: _t(9, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t1);
    });

    test('a ΔT=0 point ends its run immediately at itself', () {
      final t1 = HardFloorPoint(dayOffset: 2, value: _t(7, 0, day: 3)); // ΔT=0
      final t2 = HardFloorPoint(dayOffset: 5, value: _t(9, 0, day: 6));

      final result = groupTarget(
        anchor: _t(7, 0, day: 1),
        points: [t1, t2],
        maxDailyDelta: maxDailyDelta,
      );

      expect(result, t1);
    });
  });

  group('planGapOrRunStartDay (FR-7)', () {
    // HardFloorPoint.dayOffset is always relative to "today" (the `v` passed
    // in for THIS call) - each simulated day below is its own fresh call,
    // exactly as a real daily replanning loop would rebase it.

    test('one hardFloor point: Monday drifts, Tuesday starts the run', () {
      const preferredWakeUpTime = TimeOfDay(hour: 10, minute: 0);
      const maxDailyDelta = Duration(minutes: 30);
      final f = _utc(5, 0); // Saturday, 05:00

      // remainingPoints' dayOffset is relative to v (the real calendar-day
      // distance from v to F) - groupTarget/distribute necessarily need it
      // that way for date placement (see the groupTarget tests). v is
      // "Sunday" (day 1); F=Saturday is 6 days away from it
      // (Mon,Tue,Wed,Thu,Fri,Sat). planGapOrRunStartDay itself subtracts 1
      // from that to form the spec's own N_remaining ("days from tomorrow to
      // F, F included" = 5 for Monday).
      final monday = planGapOrRunStartDay(
        v: _utc(7, 0),
        remainingPoints: [HardFloorPoint(dayOffset: 6, value: f)],
        preferredWakeUpTime: preferredWakeUpTime,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );
      // v is the anchor "yesterday" (Sunday); planGapOrRunStartDay always
      // computes the value for the real following day (see
      // applyGapDayDrift()'s date advancement) - so "Monday" lands on v.day + 1.
      expect(monday.value, _utc(7, 30, day: 2));
      expect(monday.overrunNotificationNeeded, isFalse);

      // Tuesday: the anchor is now Monday's actual result (day 2); F is
      // still 5 days away from there (Wed,Thu,Fri,Sat + F itself).
      final tuesday = planGapOrRunStartDay(
        v: monday.value,
        remainingPoints: [HardFloorPoint(dayOffset: 5, value: f)],
        preferredWakeUpTime: preferredWakeUpTime,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );
      expect(tuesday.value, _utc(7, 0, day: 3));
      expect(tuesday.overrunNotificationNeeded, isFalse);
    });

    test(
        'two hardFloor points, FR-5 target ≠ next point: Monday starts immediately',
        () {
      const maxDailyDelta = Duration(minutes: 30);
      // v (Sunday, anchor) is day 1; the values must lie on v.day + dayOffset
      // so that groupTarget's intermediate-point check compares real dates
      // (see the groupTarget tests above). Friday is 5 days after Sunday
      // (day 6), Saturday 6 days (day 7).
      final t1 = _utc(6, 0, day: 6); // Friday, loose
      final t2 = _utc(4, 0, day: 7); // Saturday, strict

      // Monday: t1 (Friday) is 5 days from v, t2 (Saturday) 6 days.
      final monday = planGapOrRunStartDay(
        v: _utc(7, 0),
        remainingPoints: [
          HardFloorPoint(dayOffset: 5, value: t1),
          HardFloorPoint(dayOffset: 6, value: t2),
        ],
        preferredWakeUpTime: null,
        maxDailyDelta: maxDailyDelta,
        deviceUtcOffset: Duration.zero,
      );

      expect(monday.value, _utc(6, 30, day: 2));
      expect(monday.overrunNotificationNeeded, isFalse);
    });
  });

  group('updateGapDayCounter (FR-9)', () {
    test('a day with a real hardFloor resets it', () {
      expect(
        updateGapDayCounter(previousCounter: 6, dayHadRealHardFloor: true),
        0,
      );
    });

    test('a day without a hardFloor increases it by 1', () {
      expect(
        updateGapDayCounter(previousCounter: 6, dayHadRealHardFloor: false),
        7,
      );
    });

    test('rolling across several days - 6 appointment-free days before today',
        () {
      var counter = 0;
      for (var i = 0; i < 6; i++) {
        counter = updateGapDayCounter(
          previousCounter: counter,
          dayHadRealHardFloor: false,
        );
      }
      expect(counter, 6); // not yet 7 -> no firing
    });
  });

  group('coldStart (FR-10)', () {
    test(
        'days 1-5 appointment-free, no preferredWakeUpTime -> no alarm planned',
        () {
      final days = [
        _utc(0, 0, day: 1),
        _utc(0, 0, day: 2),
        _utc(0, 0, day: 3),
        _utc(0, 0, day: 4),
        _utc(0, 0, day: 5),
      ];

      final result = coldStart(
          days: days,
          preferredWakeUpTime: null,
          deviceUtcOffset: Duration.zero);

      expect(result.length, 5);
      expect(result.values.every((v) => v == null), isTrue);
    });

    test('with preferredWakeUpTime -> these days use it', () {
      final days = [_utc(0, 0, day: 1), _utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        deviceUtcOffset: Duration.zero,
      );

      expect(result[days[0]], _utc(9, 0, day: 1));
      expect(result[days[1]], _utc(9, 0, day: 2));
    });
  });

  group('computeWeekPlan (FR-8)', () {
    DateTime day(int n) => _utc(0, 0, day: n);

    test(
        'cold start: days 1-5 appointment-free, day 6 hardFloor=05:30, no preferredWakeUpTime',
        () {
      final window = [1, 2, 3, 4, 5, 6].map(day).toList();
      final events = [_meetingAt(_utc(5, 30, day: 6))];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      for (var d = 1; d <= 5; d++) {
        expect(result.valuesByDay[day(d)], isNull);
      }
      expect(result.valuesByDay[day(6)], _utc(5, 30, day: 6));
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
    });

    test(
        'docs/TODO.md T-52.3: durationToGetReadyForDay lets different days in '
        'the same window use a different lead time', () {
      final window = [1, 2, 3].map(day).toList();
      final events = [
        _meetingAt(_utc(8, 0, day: 1)),
        _meetingAt(_utc(8, 0, day: 2)),
      ];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        // Day 1 gets a 30-minute lead time, day 2 a full hour - so the same
        // 08:00 appointment produces two different hardFloors.
        durationToGetReadyForDay: (d) =>
            d.day == 1 ? const Duration(minutes: 30) : const Duration(hours: 1),
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(hours: 2),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1));
      expect(result.valuesByDay[day(2)], _utc(7, 0, day: 2));
    });

    test(
        'docs/TODO.md T-52.1: scheduleOnGapDays=false masks every day without '
        'its own appointment, cold start (no anchor anywhere)', () {
      final window = [1, 2, 3].map(day).toList();

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: false,
      );

      for (final d in window) {
        expect(result.valuesByDay[d], isNull);
      }
    });

    test(
        'docs/TODO.md T-52.1: scheduleOnGapDays=false masks drifted gap days '
        'but leaves real appointment days untouched', () {
      final window = [1, 2, 3].map(day).toList();
      // Day 3 has a real appointment; days 1-2 would otherwise drift toward
      // preferredWakeUpTime.
      final events = [_meetingAt(_utc(6, 0, day: 3))];

      final withGapDays = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 8, minute: 0),
        maxDailyDelta: const Duration(hours: 2),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );
      // Sanity check: with the toggle on, days 1-2 drift and are not null.
      expect(withGapDays.valuesByDay[day(1)], isNotNull);
      expect(withGapDays.valuesByDay[day(2)], isNotNull);
      expect(withGapDays.valuesByDay[day(3)], _utc(6, 0, day: 3));

      final withoutGapDays = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 8, minute: 0),
        maxDailyDelta: const Duration(hours: 2),
        gapDayCounter: 0,
        scheduleOnGapDays: false,
      );
      expect(withoutGapDays.valuesByDay[day(1)], isNull);
      expect(withoutGapDays.valuesByDay[day(2)], isNull);
      // The real appointment day is completely unaffected by the toggle.
      expect(withoutGapDays.valuesByDay[day(3)], _utc(6, 0, day: 3));
    });

    test(
        'one hardFloor point at the end of the window - the whole week worked '
        'through (regression test: Friday was wrong before the N_remaining<=1 fix)',
        () {
      final window = [1, 2, 3, 4, 5, 6].map(day).toList(); // Mon..Sat
      final events = [_meetingAt(_utc(5, 0, day: 6))]; // Sat, F=05:00

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0), // Sun, anchor
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 10, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      // Monday (i=1, N_F=6, N_remaining=5): holding satisfies 24min<=30min,
      // full drift (30min<=30min, boundary) -> 07:30 (matches exactly FR-7's
      // own worked test case above, "one hardFloor point: Monday drifts").
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1)); // Mon
      // Tuesday (i=2, N_remaining=4): holding at 07:30 violates
      // 37.5min>30min -> day 1 of a new run, N=5 (Tue-Sat): Tue=07:00,
      // Wed=06:30, Thu=06:00, Fri=05:30, Sat=05:00 - identical to FR-7's own
      // test case.
      expect(result.valuesByDay[day(2)], _utc(7, 0, day: 2)); // Tue
      expect(result.valuesByDay[day(3)], _utc(6, 30, day: 3)); // Wed
      expect(result.valuesByDay[day(4)], _utc(6, 0, day: 4)); // Thu
      expect(result.valuesByDay[day(5)], _utc(5, 30, day: 5)); // Fri
      expect(result.valuesByDay[day(6)],
          _utc(5, 0, day: 6)); // Sat, its own hardFloor
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);
    });

    test(
        'two hardFloor points: a loose intermediate appointment is smoothly '
        'undercut, not reset to its own hardFloor', () {
      final window = [1, 2, 3, 4].map(day).toList(); // Mon..Thu
      final events = [
        _meetingAt(_utc(8, 0, day: 3)), // Wed, loose
        _meetingAt(_utc(3, 0, day: 4)), // Thu, strict
      ];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(9, 0, day: 0), // Sun, anchor
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 90),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      // FR-5 (hypothetical, A=Sun 09:00): t_m=Thu 03:00 (strict), N_F=4
      // (distributing A->Thu over 4 days gives 04:30 on Wed, doesn't violate
      // Wed's own hardFloor of 08:00). Monday (i=1, N_remaining=3): holding
      // at 09:00 already violates 120min>90min -> Monday is itself day 1 of
      // the run, N=4: Mon=07:30.
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1)); // Mon
      // Tuesday (i=2 from the new anchor Mon=07:30, N_remaining=2 to Thu):
      // holding violates 135min>90min -> day 1 of a new run, N=3: Tue=06:00.
      expect(result.valuesByDay[day(2)], _utc(6, 0, day: 2)); // Tue
      // Wed: its own hardFloor would be 08:00, but the curve (04:30)
      // undercuts it without violating it - the curve wins, no reset to 08:00.
      expect(result.valuesByDay[day(3)], _utc(4, 30, day: 3));
      expect(result.valuesByDay[day(4)],
          _utc(3, 0, day: 4)); // Thu, its own hardFloor
      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.safetyValveTriggered, isFalse);

      // FR-16 needs, per day, the information whether the value is
      // instant-anchored (directly from a real hardFloor - the appointment
      // doesn't shift on a time zone change) or digit-anchored (from
      // preferredWakeUpTime/the curve - where the alarm-clock convention
      // applies). This exact scenario distinguishes the two: Wed lies on the
      // curve (04:30) even though the day has its own hardFloor (08:00),
      // while Thu lies exactly on its own hardFloor.
      expect(result.instantAnchoredDays, {day(4)});
    });

    // Per spec, FR-9's valve only fires without a set `preferredWakeUpTime`
    // (exception added later, docs/TODO.md T-78) - this case therefore
    // deliberately sets none.
    test(
        'safety valve: counter already at 7, no hardFloor in the window, no preferredWakeUpTime',
        () {
      final window = [1, 2, 3].map(day).toList();

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 7,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
      expect(result.safetyValveTriggered, isTrue);
    });

    // docs/TODO.md T-78 / FR-9 "exception: preferredWakeUpTime set": the
    // valve protects against blind advancement. With a preferredWakeUpTime,
    // the advancement is bounded by FR-4 (it stops exactly at the
    // preferredWakeUpTime), so there is nothing to protect against - and
    // firing here would be a one-way street: without alarms there is no
    // more ring checkpoint that could ever reset the counter.
    test('the safety valve does NOT fire when a preferredWakeUpTime is set',
        () {
      final window = [1, 2, 3].map(day).toList();

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 42, // far past the threshold
        scheduleOnGapDays: true,
      );

      expect(result.safetyValveTriggered, isFalse);
      expect(result.valuesByDay.length, 3);
      expect(result.valuesByDay.values.every((v) => v != null), isTrue,
          reason: 'every window day keeps a value, '
              'got ${result.valuesByDay}');
      // FR-4 keeps drifting toward 09:00, in 30-minute steps.
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1));
      expect(result.valuesByDay[day(3)], _utc(8, 30, day: 3));
    });
  });

  // Phase 3 (docs/scheduling-v2-spec.md, "Implementation order"):
  // reinterpretForNewOffset (FR-16) - independent of Phase 1/2, needs only
  // Phase 0. Both test cases are verbatim the spec's own "Test:" bullets
  // under FR-16.
  group('reinterpretForNewOffset (FR-16)', () {
    test(
        'location change: 09:00 in zone A (+1) stays 09:00, now in zone B (+9)',
        () {
      // 09:00 local under +1 = 08:00 UTC.
      final result = reinterpretForNewOffset(
        value: _utc(8, 0),
        oldOffset: const Duration(hours: 1),
        newOffset: const Duration(hours: 9),
      );

      // 09:00 local under +9 = 00:00 UTC - same digits, new zone.
      expect(result, _utc(0, 0));
    });

    test('daylight saving: 07:00 under CET (+1) stays 07:00 under CEST (+2)',
        () {
      // 07:00 local under +1 = 06:00 UTC.
      final result = reinterpretForNewOffset(
        value: _utc(6, 0),
        oldOffset: const Duration(hours: 1),
        newOffset: const Duration(hours: 2),
      );

      // 07:00 local under +2 = 05:00 UTC.
      expect(result, _utc(5, 0));
    });
  });
}
