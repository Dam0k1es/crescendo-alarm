import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/zone_rules.dart';

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
  group('FR-1: shifts are measured on readings', () {
    test(
        'anchor 22:00, hardFloor the next day at 05:00 -> ΔT = 7h, direction '
        '"later", not 17h "earlier"', () {
      final anchor = _utc(22, 0, day: 1);
      final floor = _utc(5, 0, day: 2);
      expect(readingDelta(anchor, floor), const Duration(hours: 7));
      // Observable: a run toward it moves LATER, one hour a day, across
      // midnight onto each day's own date.
      final run = distribute(
        anchor: anchor,
        target: floor,
        n: 7,
        maxDailyDelta: const Duration(hours: 1),
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(run.overrunNotificationNeeded, isFalse);
      expect(run.valuesByDayOffset[1], _utc(23, 0, day: 2));
      expect(run.valuesByDayOffset[2], _utc(0, 0, day: 4));
      expect(run.valuesByDayOffset[7], _utc(5, 0, day: 9));
    });

    test(
        'anchor 07:00 before a zone change (CET), hardFloor afterwards 07:00 '
        'in the new zone (JST, +8h) -> ΔT = 8h, not 0', () {
      // Both read under the rules after the change: the anchor (07:00 CET =
      // 06:00 UTC) reads 15:00 JST, the hardFloor (next day 07:00 JST =
      // 22:00 UTC the same day) reads 07:00 JST.
      final jst = fixedOffset(const Duration(hours: 9));
      final anchor = _utc(6, 0, day: 1);
      final floor = _utc(22, 0, day: 1);
      expect(
          readingDelta(readingOf(anchor, jst), readingOf(floor, jst)).abs(),
          const Duration(hours: 8));
      // Observable: a one-day run is an 8-hour jump - within an 8h bound,
      // over a bound one minute smaller.
      for (final (bound, overrun) in [
        (const Duration(hours: 8), false),
        (const Duration(hours: 7, minutes: 59), true),
      ]) {
        final run = distribute(
            anchor: anchor,
            target: floor,
            n: 1,
            maxDailyDelta: bound,
            offsetAt: jst);
        expect(run.valuesByDayOffset[1], floor);
        expect(run.overrunNotificationNeeded, overrun, reason: 'bound $bound');
      }
    });
  });

  group('distribute (FR-6)', () {
    // docs/TODO.md T-206: `_t` builds LOCAL fixtures, so the rules are the
    // process zone's, and the UTC-tagged result instants are compared in the
    // fixtures' frame (`.toLocal()`) - a frame-only change, same instants.
    test('normal case, direction "earlier"', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 5,
        maxDailyDelta: const Duration(minutes: 60),
        offsetAt: deviceOffsetAt,
      );

      expect(result.overrunNotificationNeeded, isFalse);
      // Tag_i lands on anchor.day + i (a genuine calendar-date advance per
      // day) - only the wall-clock reading is interpolated; ΔT itself is
      // wall-clock-only (FR-6/FR-1, see distribute()'s doc comment).
      expect(result.valuesByDayOffset[1]!.toLocal(), _t(7, 18, day: 2));
      expect(result.valuesByDayOffset[2]!.toLocal(), _t(6, 36, day: 3));
      expect(result.valuesByDayOffset[3]!.toLocal(), _t(5, 54, day: 4));
      expect(result.valuesByDayOffset[4]!.toLocal(), _t(5, 12, day: 5));
      expect(result.valuesByDayOffset[5]!.toLocal(), _t(4, 30, day: 6));
    });

    test('normal case, direction "later"', () {
      final result = distribute(
        anchor: _t(6, 0),
        target: _t(9, 0),
        n: 3,
        maxDailyDelta: const Duration(minutes: 90),
        offsetAt: deviceOffsetAt,
      );

      expect(result.overrunNotificationNeeded, isFalse);
      expect(result.valuesByDayOffset[1]!.toLocal(), _t(7, 0, day: 2));
      expect(result.valuesByDayOffset[2]!.toLocal(), _t(8, 0, day: 3));
      expect(result.valuesByDayOffset[3]!.toLocal(), _t(9, 0, day: 4));
    });

    test('forced overrun, N>1 - distributed over all days, not dumped', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(4, 30),
        n: 3,
        maxDailyDelta: const Duration(minutes: 60),
        offsetAt: deviceOffsetAt,
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1]!.toLocal(), _t(6, 50, day: 2));
      expect(result.valuesByDayOffset[2]!.toLocal(), _t(5, 40, day: 3));
      expect(result.valuesByDayOffset[3]!.toLocal(), _t(4, 30, day: 4));
    });

    test('forced overrun, N=1 - a full jump is not a spec defect', () {
      final result = distribute(
        anchor: _t(8, 0),
        target: _t(2, 0),
        n: 1,
        maxDailyDelta: const Duration(minutes: 60),
        offsetAt: deviceOffsetAt,
      );

      expect(result.overrunNotificationNeeded, isTrue);
      expect(result.valuesByDayOffset[1]!.toLocal(), _t(2, 0, day: 2));
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
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(result, _utc(7, 0, day: 2));
    });

    test('drift toward later, full step', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(result, _utc(7, 30, day: 2));
    });

    test('drift toward earlier, full step', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 5, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(result, _utc(6, 30, day: 2));
    });

    test('target closer than maxDailyDelta -> no overshoot', () {
      final result = applyGapDayDrift(
        v: _utc(7, 0),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 15),
        maxDailyDelta: const Duration(minutes: 30),
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(berlinOffset),
      );
      expect(onDayBefore, [tokyoMeeting]);

      final onTokyoDate = eventsForDay(
        _utc(0, 0, day: 2),
        allEvents: [tokyoMeeting],
        offsetAt: fixedOffset(berlinOffset),
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
        offsetAt: deviceOffsetAt,
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
        offsetAt: deviceOffsetAt,
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
        offsetAt: deviceOffsetAt,
      );

      expect(result, t1);
    });

    // docs/TODO.md T-139 (maintainer, 2026-10-05: "every time of every day
    // should be tested"): the same bullet worked through the whole week, not
    // only the chosen target. A=07:00 (Sun), t1(Tue)=07:00, t2(Fri)=09:00,
    // no preferredWakeUpTime. t2 is later than every value, so - FR-5's
    // precondition (T-132) - it is never a target: "t2 starts a new run" is
    // a run of length zero, every day holds 07:00 and Friday's 09:00 is only
    // a cap. No day moves, no notification.
    test('the same bullet over the whole week: every day holds 07:00', () {
      final result = _utcWeek(
        anchor: _utc(7, 0, day: 1), // Sun
        events: [
          _meetingAt(_utc(7, 0, day: 3)), // Tue, ΔT = 0
          _meetingAt(_utc(9, 0, day: 6)), // Fri
        ],
        maxDailyDelta: maxDailyDelta,
      );
      _expectUtcWeek(result, [
        for (var d = 2; d <= 7; d++) _utc(7, 0, day: d),
      ], overrun: false);
    });
  });

  group('FR-5 precondition: only a binding point is a target (T-132)', () {
    // Bullet 2, verbatim: same anchor (A=06:45, preferredWakeUpTime=07:00,
    // maxDailyDelta=30min), a single appointment at 05:00 in four days ->
    // "run toward earlier: 06:18 / 05:52 / 05:26 / 05:00, then drifts back
    // toward preferredWakeUpTime". The spec shows minutes; the exact even
    // steps are 105min / 4 = 26:15, so the values carry seconds (06:18:45,
    // 05:52:30, 05:26:15). The drift back is FR-4's 30-minute steps.
    test('a single earlier appointment in four days: an even run, then back',
        () {
      final result = _utcWeek(
        anchor: _utc(6, 45, day: 1),
        events: [_meetingAt(_utc(5, 0, day: 5))],
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        days: 7,
      );
      _expectUtcWeek(result, [
        DateTime.utc(2026, 1, 2, 6, 18, 45),
        DateTime.utc(2026, 1, 3, 5, 52, 30),
        DateTime.utc(2026, 1, 4, 5, 26, 15),
        _utc(5, 0, day: 5),
        _utc(5, 30, day: 6),
        _utc(6, 0, day: 7),
        _utc(6, 30, day: 8),
      ], overrun: false);
    });
  });

  group('FR-5 precondition, decided on the point\'s own date (T-208 shape)',
      () {
    // Bullet added 2026-10-06, verbatim: A = Sun 07:00, hardFloors Wed 05:30
    // and Fri 19:00, maxDailyDelta=30min, no preferredWakeUpTime -> Mon
    // 06:30, Tue 06:00, Wed 05:30, then 05:30 every day, no notification.
    test('an evening appointment after a morning value is only its cap', () {
      final result = _utcWeek(
        anchor: _utc(7, 0, day: 4), // Sun 4 Jan 2026
        events: [
          _meetingAt(_utc(5, 30, day: 7)), // Wed
          _meetingAt(_utc(19, 0, day: 9)), // Fri
        ],
        maxDailyDelta: const Duration(minutes: 30),
      );
      _expectUtcWeek(result, [
        _utc(6, 30, day: 5),
        _utc(6, 0, day: 6),
        _utc(5, 30, day: 7),
        _utc(5, 30, day: 8),
        _utc(5, 30, day: 9),
        _utc(5, 30, day: 10),
      ], overrun: false);
    });
  });

  group('planGapOrRunStartDay (FR-7)', () {
    // HardFloorPoint.dayOffset is always relative to "today" (the `v` passed
    // in for THIS call) - each simulated day below is its own fresh call,
    // exactly as a real daily replanning loop would rebase it.

    test('one hardFloor point: Monday drifts, Tuesday starts the run', () {
      const preferredWakeUpTime = TimeOfDay(hour: 10, minute: 0);
      const maxDailyDelta = Duration(minutes: 30);
      // On its real date (v.day + 6), as HardFloorPoint requires - the
      // reachability check (T-139) compares it as an instant.
      final f = _utc(5, 0, day: 7); // Saturday, 05:00

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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(tuesday.value, _utc(7, 0, day: 3));
      expect(tuesday.overrunNotificationNeeded, isFalse);
    });

    // docs/TODO.md T-139: every day of the bullet, not only Monday/Tuesday -
    // "Tue=07:00, Wed=06:30, Thu=06:00, Fri=05:30, Sat=05:00".
    test('one hardFloor point: the whole week as the bullet lists it', () {
      final result = _utcWeek(
        anchor: _utc(7, 0, day: 1), // Sun
        events: [_meetingAt(_utc(5, 0, day: 7))], // Sat
        preferredWakeUpTime: const TimeOfDay(hour: 10, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
      );
      _expectUtcWeek(result, [
        _utc(7, 30, day: 2), // Mon
        _utc(7, 0, day: 3), // Tue
        _utc(6, 30, day: 4), // Wed
        _utc(6, 0, day: 5), // Thu
        _utc(5, 30, day: 6), // Fri
        _utc(5, 0, day: 7), // Sat
      ], overrun: false);
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
        offsetAt: fixedOffset(Duration.zero),
      );

      expect(monday.value, _utc(6, 30, day: 2));
      expect(monday.overrunNotificationNeeded, isFalse);
    });

    // docs/TODO.md T-139, decided by the maintainer on 2026-10-05: "every
    // time of every day should be tested, and the jump should not occur at
    // all". This bullet's own week - Mon=06:30 ... Sat=04:00 in 30-minute
    // steps, no notification - is the intended behaviour. Before the fix
    // the engine planned Mon 06:30, Tue 06:00, Wed 06:00, Thu 06:00, Fri
    // 05:00, Sat 04:00 with an overrun: from Tuesday on, Friday's 06:00 has
    // ΔT=0 and FR-5 step 2 cut Saturday out of FR-7's lookahead.
    test('two hardFloor points: the whole week as the bullet lists it', () {
      final result = _utcWeek(
        anchor: _utc(7, 0, day: 1), // Sun
        events: [
          _meetingAt(_utc(6, 0, day: 6)), // Fri, loose
          _meetingAt(_utc(4, 0, day: 7)), // Sat, strict
        ],
        maxDailyDelta: const Duration(minutes: 30),
      );
      _expectUtcWeek(result, [
        _utc(6, 30, day: 2), // Mon
        _utc(6, 0, day: 3), // Tue
        _utc(5, 30, day: 4), // Wed
        _utc(5, 0, day: 5), // Thu
        _utc(4, 30, day: 6), // Fri
        _utc(4, 0, day: 7), // Sat
      ], overrun: false);
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
          offsetAt: fixedOffset(Duration.zero));

      expect(result.length, 5);
      expect(result.values.every((v) => v == null), isTrue);
    });

    test('with preferredWakeUpTime -> these days use it', () {
      final days = [_utc(0, 0, day: 1), _utc(0, 0, day: 2)];

      final result = coldStart(
        days: days,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
      // FR-4 keeps drifting toward 09:00, in 30-minute steps - every day.
      expect(result.valuesByDay[day(1)], _utc(7, 30, day: 1));
      expect(result.valuesByDay[day(2)], _utc(8, 0, day: 2));
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

    // docs/TODO.md T-206: this is the arithmetic of the WITHDRAWN FR-16
    // "daylight saving" bullet (shift by the offset difference). The spec
    // now says a DST change re-resolves planned clock times and changes
    // nothing; this case stays as the test of the legacy function, which
    // Checkpoint 2 still uses for a plan stored without planned clock times
    // (FR-16 step 2, the upgrade window).
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

  // docs/TODO.md T-206: the daylight-saving "Test:" bullets added to the spec
  // on 2026-09-28, verbatim (same zones, dates and numbers).
  _t206SpecBullets();
}

/// A week planned at a fixed UTC+0 offset, no lead times: the window is the
/// [days] days after [anchor]'s own date (docs/TODO.md T-139's full-week
/// assertions).
WeekPlanResult _utcWeek({
  required DateTime anchor,
  required List<Meeting> events,
  TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
  int days = 6,
}) =>
    computeWeekPlan(
      window: [
        for (var i = 1; i <= days; i++)
          DateTime.utc(anchor.year, anchor.month, anchor.day + i)
      ],
      lastEffectiveWakeTime: anchor,
      allEvents: events,
      offsetAt: fixedOffset(Duration.zero),
      durationToWakeUp: Duration.zero,
      durationToGetReadyForDay: (_) => Duration.zero,
      preferredWakeUpTime: preferredWakeUpTime,
      maxDailyDelta: maxDailyDelta,
      gapDayCounter: 0,
      scheduleOnGapDays: true,
    );

/// Asserts EVERY day of [result] (in window order) and the overrun flag.
void _expectUtcWeek(WeekPlanResult result, List<DateTime> expected,
    {required bool overrun}) {
  final actual = result.valuesByDay.values.toList();
  expect(actual, expected,
      reason: 'every day of the week, in order (got $actual)');
  expect(result.overrunNotificationNeeded, overrun);
}

// ---------------------------------------------------------------------------
// docs/TODO.md T-206 - daylight saving within one zone. Every case below is
// one of the spec's new "Test:" bullets (FR-1, FR-2, FR-4, FR-6, FR-10),
// taken verbatim; the expected instants were computed independently with
// Python `zoneinfo` (T-206 requirements, section 8). The device zone's RULES
// are injected (`zoneRules`), never the process zone, so every CI leg checks
// the same digits. Derived cases live in test/t206_dst_planning_test.dart.
// ---------------------------------------------------------------------------

late ZoneOffsetAt _berlinRules;
late ZoneOffsetAt _nuukRules;
late ZoneOffsetAt _santiagoRules;
late tz.Location _berlin;
late tz.Location _nuuk;

List<DateTime> _window(tz.Location loc, int year, int month, int day) =>
    List.generate(7, (i) => tz.TZDateTime(loc, year, month, day + i));

Meeting _event(DateTime instant, tz.Location loc) => Meeting(
      from: tz.TZDateTime.from(instant, loc),
      to: tz.TZDateTime.from(instant.add(const Duration(hours: 1)), loc),
      isAllDay: false,
      startTimeZone: loc.name,
      endTimeZone: loc.name,
    );

WeekPlanResult _plan({
  required List<DateTime> window,
  required DateTime? anchor,
  required ZoneOffsetAt rules,
  DateTime? anchorClockTime,
  List<Meeting> events = const [],
  Duration wakeUp = Duration.zero,
  TimeOfDay? preferred,
  int maxDeltaMinutes = 30,
}) =>
    computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: anchor,
      lastEffectiveClockTime: anchorClockTime,
      allEvents: events,
      offsetAt: rules,
      durationToWakeUp: wakeUp,
      durationToGetReadyForDay: (_) => Duration.zero,
      preferredWakeUpTime: preferred,
      maxDailyDelta: Duration(minutes: maxDeltaMinutes),
      gapDayCounter: 0,
      scheduleOnGapDays: true,
    );

/// Asserts every window day's value exactly (microseconds), naming the day.
void _expectValues(WeekPlanResult result, List<DateTime> window,
    List<DateTime> expected) {
  for (var i = 0; i < window.length; i++) {
    expect(result.valuesByDay[window[i]], expected[i],
        reason: 'window day ${window[i]}: expected ${expected[i]}, '
            'got ${result.valuesByDay[window[i]]}');
  }
}

void _t206SpecBullets() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    _berlin = tz.getLocation('Europe/Berlin');
    _nuuk = tz.getLocation('America/Nuuk');
    _berlinRules = zoneRules(_berlin);
    _nuukRules = zoneRules(_nuuk);
    _santiagoRules = zoneRules(tz.getLocation('America/Santiago'));
  });

  group('FR-1 (T-206: instants for bounds, readings for shifts)', () {
    // Observable form (requirements b.5): the anchor, the hardFloor on its
    // day, maxDailyDelta 15, no preferredWakeUpTime. ΔT = 0 means no run
    // starts (FR-5 step 2's ΔT = 0 point): 07:00 by the clock every day and
    // the hardFloor day exactly its instant, no notification.
    test(
        'Test (DST, spring, T-206): Europe/Berlin, anchor Sat 28 Mar 2026 '
        '07:00 CET (06:00 UTC), hardFloor Mon 30 Mar 2026 07:00 CEST (05:00 '
        'UTC) -> ΔT = 0 (same reading), although the instants are 47h apart, '
        'not 48h', () {
      final anchor = DateTime.utc(2026, 3, 28, 6, 0);
      final hardFloorInstant = DateTime.utc(2026, 3, 30, 5, 0);
      expect(hardFloorInstant.difference(anchor), const Duration(hours: 47));
      final window = _window(_berlin, 2026, 3, 29);
      final result = _plan(
        window: window,
        anchor: anchor,
        rules: _berlinRules,
        events: [_event(hardFloorInstant, _berlin)],
        maxDeltaMinutes: 15,
      );
      _expectValues(result, window, [
        for (var d = 29; d <= 35; d++) DateTime.utc(2026, 3, d, 5, 0),
      ]);
      expect(result.valuesByDay[window[1]], hardFloorInstant);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test(
        'Test (DST, autumn, T-206): anchor Sat 24 Oct 2026 07:00 CEST (05:00 '
        'UTC), hardFloor Mon 26 Oct 2026 07:00 CET (06:00 UTC) -> ΔT = 0, '
        'although the instants are 49h apart', () {
      final anchor = DateTime.utc(2026, 10, 24, 5, 0);
      final hardFloorInstant = DateTime.utc(2026, 10, 26, 6, 0);
      expect(hardFloorInstant.difference(anchor), const Duration(hours: 49));
      final window = _window(_berlin, 2026, 10, 25);
      final result = _plan(
        window: window,
        anchor: anchor,
        rules: _berlinRules,
        events: [_event(hardFloorInstant, _berlin)],
        maxDeltaMinutes: 15,
      );
      _expectValues(result, window, [
        for (var d = 25; d <= 31; d++) DateTime.utc(2026, 10, d, 6, 0),
      ]);
      expect(result.valuesByDay[window[1]], hardFloorInstant);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test(
        'Test (order, T-206): Europe/Berlin, Sun 25 Oct 2026, a planned '
        'reading of 02:30 (it occurs at 00:30 UTC and at 01:30 UTC) and a '
        'hardFloor of 00:45 UTC (the first 02:45) -> the value is 00:45 UTC: '
        'R_plan first (01:30 UTC, the later occurrence), then the cap on '
        'instants', () {
      final window = _window(_berlin, 2026, 10, 25);
      final result = _plan(
        window: window,
        // Sat 24 Oct 02:30 CEST.
        anchor: DateTime.utc(2026, 10, 24, 0, 30),
        rules: _berlinRules,
        preferred: const TimeOfDay(hour: 2, minute: 30),
        events: [_event(DateTime.utc(2026, 10, 25, 0, 45), _berlin)],
      );
      expect(result.valuesByDay[window[0]], DateTime.utc(2026, 10, 25, 0, 45),
          reason: 'capping on readings (02:30 is before 02:45, keep it) '
              'would give 01:30 UTC and miss the appointment by 45 minutes');
      expect(result.instantAnchoredDays, contains(window[0]));
      expect(result.plannedClockTimes.containsKey(window[0]), isFalse);
    });

    test(
        'Test (TZ-2a, America/Nuuk): a planned reading of Sat 28 Mar 2026 '
        '23:30 (inside the gap 23:00 -> 00:00) -> 29 Mar 00:59 UTC, which '
        'reads 22:59 on 28 Mar, not 00:00 on 29 Mar; the day\'s planned clock '
        'time stays 23:30', () {
      final value = resolvePlannedClockTime(wall(2026, 3, 28, 23, 30), _nuukRules);
      expect(value, DateTime.utc(2026, 3, 29, 0, 59));
      expect(value.isUtc, isTrue);
      expect(readingOf(value, _nuukRules), wall(2026, 3, 28, 22, 59));

      // The planned clock time stays 23:30 (plan form: T-206 test T52).
      final window = _window(_nuuk, 2026, 3, 28);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 3, 28, 1, 30), // Fri 27 Mar 23:30 (-2)
        rules: _nuukRules,
      );
      expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 29, 0, 59));
      expect(result.plannedClockTimes[window[0]], wall(2026, 3, 28, 23, 30));
    });

    test(
        'Test (TZ-2a) counter-tests, plain R: Europe/Berlin 29 Mar 2026 02:30 '
        '-> 01:00 UTC (03:00 CEST, same date); America/Santiago 6 Sep 2026 '
        '00:30 -> 04:00 UTC (01:00, same date); America/Nuuk 24 Oct 2026 '
        '23:30, a repeated reading -> 25 Oct 01:30 UTC (the later occurrence, '
        'still 24 Oct 23:30 by the clock)', () {
      final berlin = resolvePlannedClockTime(wall(2026, 3, 29, 2, 30), _berlinRules);
      expect(berlin, DateTime.utc(2026, 3, 29, 1, 0));
      expect(readingOf(berlin, _berlinRules), wall(2026, 3, 29, 3, 0));

      final santiago =
          resolvePlannedClockTime(wall(2026, 9, 6, 0, 30), _santiagoRules);
      expect(santiago, DateTime.utc(2026, 9, 6, 4, 0));
      expect(readingOf(santiago, _santiagoRules), wall(2026, 9, 6, 1, 0));

      final nuuk = resolvePlannedClockTime(wall(2026, 10, 24, 23, 30), _nuukRules);
      expect(nuuk, DateTime.utc(2026, 10, 25, 1, 30));
      expect(readingOf(nuuk, _nuukRules), wall(2026, 10, 24, 23, 30));
    });
  });

  group('FR-2 (T-206: day assignment by the rules at the appointment)', () {
    test(
        'Test (DST inside the window, T-206): device on Europe/Berlin, '
        'planning on Sat 28 Mar 2026 (CET, +1), an appointment Mon 30 Mar 2026 '
        '00:30 CEST (29 Mar 22:30 UTC), no lead times -> it belongs to Monday '
        '30 Mar, and hardFloor(Mon) = 29 Mar 22:30 UTC; not Sunday 29 Mar', () {
      final event = _event(DateTime.utc(2026, 3, 29, 22, 30), _berlin);
      final sunday = tz.TZDateTime(_berlin, 2026, 3, 29);
      final monday = tz.TZDateTime(_berlin, 2026, 3, 30);

      expect(eventsForDay(monday, allEvents: [event], offsetAt: _berlinRules),
          [event]);
      expect(eventsForDay(sunday, allEvents: [event], offsetAt: _berlinRules),
          isEmpty,
          reason: 'under the planning day\'s +1 it would read Sunday 23:30');
      DateTime? hf(DateTime day) => hardFloor(
            day: day,
            allEvents: [event],
            offsetAt: _berlinRules,
            durationToWakeUp: Duration.zero,
            durationToGetReady: Duration.zero,
          );
      expect(hf(monday), DateTime.utc(2026, 3, 29, 22, 30));
      expect(hf(sunday), isNull);

      // The autumn mirror (requirements T10): Mon 26 Oct 23:30 CET (22:30
      // UTC) belongs to 26 Oct - under +2 it would read 27 Oct 00:30.
      final autumn = _event(DateTime.utc(2026, 10, 26, 22, 30), _berlin);
      expect(
          eventsForDay(tz.TZDateTime(_berlin, 2026, 10, 26),
              allEvents: [autumn], offsetAt: _berlinRules),
          [autumn]);
      expect(
          eventsForDay(tz.TZDateTime(_berlin, 2026, 10, 27),
              allEvents: [autumn], offsetAt: _berlinRules),
          isEmpty);
    });
  });

  group('FR-4 (T-206: daylight saving, no hardFloor in the window)', () {
    test(
        'Test (DST, spring): V = Sat 28 Mar 2026 07:00 CET, '
        'preferredWakeUpTime=null -> Sun 29 Mar 07:00 CEST (05:00 UTC), and '
        '07:00 on every day after; not 08:00', () {
      final window = _window(_berlin, 2026, 3, 29);
      for (final (preferred, md) in [
        (null, 30),
        (const TimeOfDay(hour: 7, minute: 0), 15),
      ]) {
        final result = _plan(
          window: window,
          anchor: DateTime.utc(2026, 3, 28, 6, 0),
          rules: _berlinRules,
          preferred: preferred,
          maxDeltaMinutes: md,
        );
        _expectValues(result, window, [
          for (var d = 29; d <= 35; d++) DateTime.utc(2026, 3, d, 5, 0),
        ]);
        for (final day in window) {
          expect(result.plannedClockTimes[day],
              wall(day.year, day.month, day.day, 7, 0),
              reason: 'planned clock time of $day (P $preferred, md $md)');
        }
        expect(result.overrunNotificationNeeded, isFalse);
      }
    });

    test(
        'Test (DST, autumn): V = Sat 24 Oct 2026 07:00 CEST, '
        'preferredWakeUpTime=null -> Sun 25 Oct 07:00 CET (06:00 UTC), and '
        '07:00 on every day after; not 06:00', () {
      final window = _window(_berlin, 2026, 10, 25);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 10, 24, 5, 0),
        rules: _berlinRules,
      );
      _expectValues(result, window, [
        for (var d = 25; d <= 31; d++) DateTime.utc(2026, 10, d, 6, 0),
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test(
        'Test (DST, held reading in the skipped hour): V = Sat 28 Mar 2026 '
        '02:30 CET (planned clock time 02:30), preferredWakeUpTime=null -> Sun '
        '29 Mar 03:00 CEST (01:00 UTC, TZ-1), Mon 30 Mar 02:30 CEST (00:30 '
        'UTC), and 02:30 on every day after; not 03:00 from Sunday on', () {
      final window = _window(_berlin, 2026, 3, 29);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 3, 28, 1, 30),
        anchorClockTime: wall(2026, 3, 28, 2, 30),
        rules: _berlinRules,
      );
      _expectValues(result, window, [
        DateTime.utc(2026, 3, 29, 1, 0),
        for (var d = 30; d <= 35; d++) DateTime.utc(2026, 3, d, 0, 30),
      ]);
      for (final day in window) {
        expect(result.plannedClockTimes[day],
            wall(day.year, day.month, day.day, 2, 30));
      }
    });

    test(
        'Test (DST, preferredWakeUpTime in the repeated hour): '
        'preferredWakeUpTime=02:30, V = Sat 24 Oct 2026 02:30 CEST -> Sun 25 '
        'Oct 02:30 CET (01:30 UTC, the later occurrence)', () {
      final window = _window(_berlin, 2026, 10, 25);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 10, 24, 0, 30),
        rules: _berlinRules,
        preferred: const TimeOfDay(hour: 2, minute: 30),
      );
      // Every day, not only the first two (docs/TODO.md T-139's "every
      // time of every day"): 02:30 CET, the later occurrence on Sunday.
      _expectValues(result, window, [
        for (var d = 25; d <= 31; d++) DateTime.utc(2026, 10, d, 1, 30),
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test(
        'Test (DST, a real drift stays limited): V = Sat 28 Mar 2026 07:00 '
        'CET, preferredWakeUpTime=09:00, maxDailyDelta=30min -> Sun 07:30 '
        'CEST, Mon 08:00, Tue 08:30, Wed 09:00; not 08:30 on Sunday', () {
      final window = _window(_berlin, 2026, 3, 29);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 3, 28, 6, 0),
        rules: _berlinRules,
        preferred: const TimeOfDay(hour: 9, minute: 0),
        maxDeltaMinutes: 30,
      );
      _expectValues(result, window, [
        DateTime.utc(2026, 3, 29, 5, 30),
        DateTime.utc(2026, 3, 30, 6, 0),
        DateTime.utc(2026, 3, 31, 6, 30),
        DateTime.utc(2026, 4, 1, 7, 0),
        DateTime.utc(2026, 4, 2, 7, 0),
        DateTime.utc(2026, 4, 3, 7, 0),
        DateTime.utc(2026, 4, 4, 7, 0),
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group('FR-6 (T-206: shifts are measured on readings)', () {
    test(
        'Test (DST, no shift across a change, T-206): Europe/Berlin, A = Fri '
        '27 Mar 2026 07:00 CET, the only hardFloor Tue 31 Mar 07:00 CEST '
        '(appointment 07:30 CEST, 30 min to wake up, no getting-ready time), '
        'no preferredWakeUpTime, maxDailyDelta 15 or 30 min -> 07:00 by the '
        'clock on every day, no notification. The same with the appointment '
        'on Mon 30 Mar instead', () {
      final window = _window(_berlin, 2026, 3, 28);
      for (final appointment in [
        DateTime.utc(2026, 3, 31, 5, 30), // Tue 07:30 CEST
        DateTime.utc(2026, 3, 30, 5, 30), // Mon 07:30 CEST
      ]) {
        for (final md in [15, 30]) {
          final result = _plan(
            window: window,
            anchor: DateTime.utc(2026, 3, 27, 6, 0),
            rules: _berlinRules,
            events: [_event(appointment, _berlin)],
            wakeUp: const Duration(minutes: 30),
            maxDeltaMinutes: md,
          );
          final label = 'appointment $appointment, md $md';
          expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 28, 6, 0),
              reason: '$label: Sat 28 Mar stays 07:00 CET, no run starts');
          for (var i = 1; i < 7; i++) {
            expect(result.valuesByDay[window[i]],
                DateTime.utc(2026, 3, 28 + i, 5, 0),
                reason: '$label: ${window[i]} is 07:00 CEST');
          }
          expect(result.overrunNotificationNeeded, isFalse, reason: label);
        }
      }
    });

    test(
        'Test (DST, a real shift across a change is measured on readings, '
        'T-206): A = Sat 28 Mar 2026 07:00 CET, F = Sun 29 Mar 06:00 CEST '
        '(04:00 UTC), N=1 -> ΔT = 60min (not 0, not 120): with '
        'maxDailyDelta=60min no notification, with 45min a notification. F = '
        'Sun 29 Mar 05:00 CEST (03:00 UTC), maxDailyDelta=30min -> ΔT = '
        '120min, notification. In each case the value is exactly F', () {
      final window = _window(_berlin, 2026, 3, 29);
      for (final (f, md, notify) in [
        (DateTime.utc(2026, 3, 29, 4, 0), 60, false),
        (DateTime.utc(2026, 3, 29, 4, 0), 45, true),
        (DateTime.utc(2026, 3, 29, 3, 0), 30, true),
      ]) {
        final result = _plan(
          window: window,
          anchor: DateTime.utc(2026, 3, 28, 6, 0),
          rules: _berlinRules,
          events: [_event(f, _berlin)],
          maxDeltaMinutes: md,
        );
        // Every day: F on its own day, then F's reading held (no
        // preferredWakeUpTime, nothing further in the window).
        _expectValues(result, window, [
          for (var i = 0; i < 7; i++)
            DateTime.utc(2026, 3, 29 + i, f.hour, f.minute),
        ]);
        expect(result.overrunNotificationNeeded, notify,
            reason: 'F $f, md $md');
      }
    });
  });

  group('FR-10 (T-206)', () {
    test(
        'Test (DST, T-206): Europe/Berlin, window Sat 28 Mar - Fri 3 Apr 2026, '
        'no appointment, preferredWakeUpTime=07:00, no lastEffectiveWakeTime '
        '-> 07:00 by the clock every day: 28 Mar 06:00 UTC, from 29 Mar on '
        '05:00 UTC', () {
      final window = _window(_berlin, 2026, 3, 28);
      final result = _plan(
        window: window,
        anchor: null,
        rules: _berlinRules,
        preferred: const TimeOfDay(hour: 7, minute: 0),
      );
      _expectValues(result, window, [
        DateTime.utc(2026, 3, 28, 6, 0),
        for (var d = 29; d <= 34; d++) DateTime.utc(2026, 3, d, 5, 0),
      ]);
    });
  });
}
