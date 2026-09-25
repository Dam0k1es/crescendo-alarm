import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

// Regressions from the independent spec review (2026-09-11).
//
// This file is deliberately kept separate from `scheduling_v2_test.dart`:
// that file's header promises "Every test case here is taken verbatim (same
// numbers) from the 'Test:' bullets under the matching FR in the spec", and
// that promise should stay true. The cases here are *derived* from the FR
// text, not copied from a test bullet - they cover exactly the gaps the
// review found, because the spec only works its own bullets through for the
// simplest case in each instance.
//
// Each case names the id under which it is tracked in docs/TODO.md.

DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 1, day, hour, minute);

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

void main() {
  group('FR-5 step 2: a ΔT=0 point ends the run at itself (T-104)', () {
    // The spec sentence carries no positional caveat:
    //
    //   "A point with `ΔT=0` relative to `A` ends the run immediately at
    //    itself - it never counts as compatible with either direction, and
    //    is NEVER grouped with a following point."
    //
    // The spec's own test bullet places the ΔT=0 point at position 1
    // (`A=07:00, t1(Tue)=07:00, t2(Fri)=09:00`) - exactly where a check on
    // `points.first` alone would already suffice. If it sits further back,
    // the same sentence still applies.

    test('ΔT=0 at position 2 ends the run just as it does at position 1', () {
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(8, 0, day: 2)),
          HardFloorPoint(dayOffset: 2, value: _utc(7, 0, day: 3)), // ΔT = 0
          HardFloorPoint(dayOffset: 3, value: _utc(5, 0, day: 4)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      // The run must not be grouped past the ΔT=0 point.
      expect(result.dayOffset, 2);
      expect(result.value, _utc(7, 0, day: 3));
    });

    test('the spec\'s own case (ΔT=0 at position 1) stays unchanged', () {
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(7, 0, day: 2)), // ΔT = 0
          HardFloorPoint(dayOffset: 4, value: _utc(9, 0, day: 5)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 1);
    });

    test('with no ΔT=0 point, grouping still reaches the last point', () {
      // Counter-check: the change must not narrow FR-5 step 1.
      // Spec bullet 1: A=08:00, t1(day2)=07:00, t2(day4)=06:00 -> one run over
      // both. Same numbers here, purely as a guard against over-correction.
      final result = groupTarget(
        anchor: _utc(8, 0),
        points: [
          HardFloorPoint(dayOffset: 2, value: _utc(7, 0, day: 3)),
          HardFloorPoint(dayOffset: 4, value: _utc(6, 0, day: 5)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 4);
    });

    test('a ΔT=0 point keeps shrinking if it violates an intermediate point',
        () {
      // Step 2 caps the run from above; step 1's shrinking still applies
      // below that cap. Anchor 09:00, t1(day1)=06:00 (strict),
      // t2(day2)=09:00 (ΔT=0). Distributing A->t2 is flat at 09:00 and
      // violates t1 (09:00 is after 06:00) -> t_m must shrink to t1.
      final result = groupTarget(
        anchor: _utc(9, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(6, 0, day: 2)),
          HardFloorPoint(dayOffset: 2, value: _utc(9, 0, day: 3)), // ΔT = 0
        ],
        maxDailyDelta: const Duration(minutes: 60),
      );

      expect(result.dayOffset, 1);
    });
  });

  group(
      'FR-6: the overrun notification must not be skipped even at N=1 (T-105)',
      () {
    // FR-6, the reporting duty:
    //
    //   "On every excess over `maxDailyDelta` (`N=1` OR distributed) the
    //    user is notified once."
    //
    // and the matching worked case:
    //
    //   "Test (overrun, `N=1`): A=08:00, F=02:00, N=1, maxDailyDelta=60min
    //    -> full 6h jump, notification - not a spec defect."
    //
    // The exception FR-6 grants for `N=1` concerns the *size of the jump*
    // ("no distribution possible"), not the notification. `distribute` sets
    // the flag correctly; the path where a day gets its own `hardFloor`
    // assigned directly used to bypass `distribute` entirely.
    //
    // Exactly `window[0]` is affected: for every later window day, the
    // previous day still runs through FR-7's check, which either keeps the
    // remaining jump small or starts a run there (and then `distribute`
    // reports it). `window[0]`'s anchor is the value that rang yesterday -
    // no such check happens for it anymore.

    test('a single appointment on window[0], a jump larger than maxDailyDelta',
        () {
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        // rang yesterday at 07:00
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(1, 0, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      // The value itself is FR-compliant: FR-2's upper bound forces 01:00,
      // and FR-6 permits the full jump, because N=1.
      expect(result.valuesByDay[window[0]], _utc(1, 0, day: 1));
      // It still has to be reported: 6h > 30min.
      expect(result.overrunNotificationNeeded, isTrue);
    });

    test('the same setup with a small jump does not report', () {
      // Counter-check against over-correction: 20min <= 30min.
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(6, 40, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 40, day: 1));
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test('a jump exactly at maxDailyDelta does not report', () {
      // FR-6's condition is "> maxDailyDelta"; the boundary itself is allowed.
      final window = List.generate(3, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 0),
        allEvents: [_meetingAt(_utc(6, 30, day: 1))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group(
      'FR-9: the valve keeps reporting as long as its condition holds (T-107)',
      () {
    // FR-9:
    //
    //   "Once the counter reaches >= 7, automatic advancement is stopped and
    //    the user is notified."
    //
    // The spec names exactly ONE exception: "The valve only fires if no
    // `preferredWakeUpTime` is set." FR-10 governs exclusively the *values*
    // when there's no anchor ("Without: no alarm planned"), never the
    // notification.
    //
    // That is exactly where the bug lived: once the valve had emptied the
    // window once, `lastEffectiveWakeTime` was `null` the next day, and the
    // cold-start branch hard-returned `safetyValveTriggered: false` - even
    // though the counter kept running and nothing was still being planned.

    test('no anchor, counter 7, no preferredWakeUpTime: the valve holds', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 7,
        scheduleOnGapDays: true,
      );

      expect(result.safetyValveTriggered, isTrue);
      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
    });

    test(
        'the same with preferredWakeUpTime set does not report (FR-9\'s exception)',
        () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 42,
        scheduleOnGapDays: true,
      );

      expect(result.safetyValveTriggered, isFalse);
      expect(result.valuesByDay.values.every((v) => v != null), isTrue,
          reason:
              'FR-9\'s exception: with preferredWakeUpTime, advancement continues');
    });

    test('no anchor, below the threshold, does not report', () {
      // Counter-check: the threshold itself stays at >= 7. FR-9's own test
      // case for this ("counter stands at 6 ... no firing") had so far only
      // been represented in the suite as an addition loop over
      // `updateGapDayCounter`, never as a call to `computeWeekPlan`.
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: null,
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 6,
        scheduleOnGapDays: true,
      );

      expect(result.safetyValveTriggered, isFalse);
    });

    test('with an anchor, the existing valve path stays unchanged', () {
      // Counter-check against over-correction: the branch with an anchor
      // still reports exactly as before.
      final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

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

      expect(result.safetyValveTriggered, isTrue);
    });
  });

  group('FR-6: the 12-hour threshold of direction resolution (T-115)', () {
    // FR-6, "Clarification of ΔT":
    //
    //   "The ambiguity in determining direction is resolved as in FR-1 (the
    //    variant with `|Δ| <= 12h` wins)."
    //
    // This threshold carries the module's entire midnight handling - it's
    // the reason "22:00 -> 05:00 the next day" reads as +7h and not as -17h.
    // It had not appeared in the suite before: the largest distance checked
    // was two hours.
    //
    // Checked here are the two values IMMEDIATELY next to the threshold.
    // They bracket it on both sides at 12:00 +/- one minute, and so catch
    // any shift or accidental removal of the wraparound resolution.
    //
    // The value ON the threshold (exactly 12:00) is deliberately missing
    // here: there, both readings satisfy `|Δ| <= 12h`, so the rule doesn't
    // choose, and the spec text doesn't decide the case. Fixing it here
    // would mean inventing the expected behaviour ourselves. See
    // docs/TODO.md T-115.

    test('a distance of 11:59 is read as "earlier"', () {
      final result = applyGapDayDrift(
        v: _utc(18, 59, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      // -11:59 wins against +12:01, so backward, capped at 30min.
      expect(result, _utc(18, 29, day: 2));
    });

    test('a distance of 12:01 is read as "later"', () {
      final result = applyGapDayDrift(
        v: _utc(19, 1, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: Duration.zero,
      );

      // +11:59 wins against -12:01, so forward.
      expect(result, _utc(19, 31, day: 2));
    });
  });

  // ---------------------------------------------------------------------
  // Safeguards (T-118): properties that are RIGHT today, clearly decided by
  // the spec - and were covered by no test.
  //
  // Each one stems from a case whose core is an open spec decision (T-119
  // through T-122). The part that is already decided can still be pinned
  // down regardless, and that is the basis against which a later decision
  // can be formulated at all.
  //
  // For each one, a mutation is on record that turns it red and that stays
  // invisible today in the rest of the suite.
  // ---------------------------------------------------------------------

  group('FR-2: day assignment at the midnight boundary (T-118a)', () {
    // FR-2: "The device's time zone at the moment of evaluation - never the
    // appointment's own zone - decides which calendar day the instant is
    // assigned to."
    //
    // At a CONSTANT offset this is unambiguously decided. The existing FR-2
    // time zone test checks the *source* of the offset, never its sign and
    // never a day boundary: its appointment sits at 18:00 UTC, where +/- one
    // hour falls on no other day.
    //
    // Mutation this catches: in `eventsForDay`, `add(deviceUtcOffset)` ->
    // `subtract(deviceUtcOffset)`. It is currently invisible in
    // scheduling_v2_test, _dst_test and _tz_test.

    const offset = Duration(hours: 2); // July, Europe/Berlin

    test('23:30 local time belongs to the current day', () {
      final result = hardFloor(
        day: DateTime.utc(2026, 7, 15),
        allEvents: [_meetingAt(DateTime.utc(2026, 7, 15, 21, 30))],
        deviceUtcOffset: offset,
        durationToWakeUp: Duration.zero,
        durationToGetReady: Duration.zero,
      );

      expect(result, DateTime.utc(2026, 7, 15, 21, 30));
    });

    test('00:30 local time belongs to the FOLLOWING day, not the current one',
        () {
      final event = _meetingAt(DateTime.utc(2026, 7, 15, 22, 30));

      expect(
        hardFloor(
          day: DateTime.utc(2026, 7, 15),
          allEvents: [event],
          deviceUtcOffset: offset,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        isNull,
        reason: 'local 00:30 on the 16th - not the 15th',
      );
      expect(
        hardFloor(
          day: DateTime.utc(2026, 7, 16),
          allEvents: [event],
          deviceUtcOffset: offset,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        ),
        DateTime.utc(2026, 7, 15, 22, 30),
      );
    });
  });

  group('FR-2: hardFloor may lie before midnight of its own day (T-118b)', () {
    // FR-2's formula has no clamp to its own day:
    //
    //   hardFloor(day) = earliest non-all-day appointment on this day
    //                    - durationToWakeUp - durationToGetReady
    //
    // A clamp would be exactly the harm case FR-2 names ("a later value
    // means missing a real appointment"): for an appointment at 00:30, a
    // clamp would only wake at midnight, i.e. 30 minutes before an
    // appointment that's set up with an hour of lead time.
    //
    // Mutation this catches: clamping the result to midnight of its own day.
    // Currently invisible in scheduling_v2_test, _dst_test, _audit_test and
    // replan_test.
    //
    // The test also establishes that a value's date and its day key CAN
    // diverge - the precondition for any decision on T-120.

    test(
        'an appointment at 00:30 with 30min lead each -> wake value the day before',
        () {
      final result = hardFloor(
        day: DateTime.utc(2026, 3, 12),
        allEvents: [_meetingAt(DateTime.utc(2026, 3, 12, 0, 30))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReady: const Duration(minutes: 30),
      );

      expect(result, DateTime.utc(2026, 3, 11, 23, 30));
      expect(result!.day, 11, reason: 'the value lies on the DAY BEFORE');
    });
  });

  group(
      'FR-9: the valve never wipes out a day that has something to do (T-118c)',
      () {
    // FR-9's "stopped" concerns ADVANCEMENT. Together with FR-2 ("never
    // later ... a later value means missing a real appointment") and
    // FR-5/FR-7 (a run must be planned toward a future real point), that
    // yields two constraints, both of which live in the valve condition
    // today and both of which were uncovered.
    //
    // Invisible, because every existing valve test runs with an EMPTY
    // calendar: there, `ownHardFloor` is always null and `remaining` is
    // always empty, so neither sub-condition is ever false.
    //
    // What they guard against: any simplification to "counter >= 7 ->
    // everything null" - the most literal reading of FR-9 and thus the most
    // likely cleanup change. Losing them would be a silent alarm on a day
    // with a real appointment.

    test('a day with its own appointment keeps its value', () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: [_meetingAt(_utc(8, 0, day: 11))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], isNotNull,
          reason: 'null would mean guaranteed missing the appointment');
      // The value is 07:00, not 08:00 (docs/TODO.md T-132): without
      // `preferredWakeUpTime`, FR-4 holds at the anchor's time of day, and
      // FR-2's upper bound of 08:00 explicitly permits any earlier value
      // ("always allowed"). Until 2026-09-11 this read 08:00 - that was the
      // bug a device report made visible: `hardFloor` was treated as a
      // target instead of as a cap.
      expect(result.valuesByDay[window[0]], _utc(7, 0, day: 11));
    });

    test('days BEFORE an appointment in the window keep their value', () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: [_meetingAt(_utc(6, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
        scheduleOnGapDays: true,
      );

      for (var i = 0; i < window.length; i++) {
        expect(result.valuesByDay[window[i]], isNotNull,
            reason:
                'a run toward the appointment on the last window day is under way');
      }
    });

    test('with no appointment at all, the valve still fires', () {
      // Counter-check against over-correction.
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 10),
        allEvents: const [],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 42,
        scheduleOnGapDays: true,
      );

      expect(result.safetyValveTriggered, isTrue);
      expect(result.valuesByDay.values.every((v) => v == null), isTrue);
    });
  });

  group('FR-2/FR-3: a capped day is instant-anchored (T-118d)', () {
    // When a curve value is capped at its own `hardFloor`, the value
    // afterward unambiguously comes "directly from a real hardFloor" (FR-3)
    // - so it's instant-anchored and must NOT travel digit-for-digit on a
    // time zone change.
    //
    // This branch was never exercised: the only positive assertion about
    // `instantAnchoredDays` in the suite concerns a day that gets its
    // hardFloor via the `remaining.isEmpty` branch, and the only neighboring
    // test explicitly checks the OPPOSITE case (the curve wins, no reset).
    // Mutation: remove `if (clampedToOwnHardFloor)
    // instantAnchoredDays.add(day);` - currently invisible in five test
    // files.

    test('a curve value above its own hardFloor is capped and anchored', () {
      final window = List.generate(5, (i) => _utc(0, 0, day: 11 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(9, 0, day: 10),
        allEvents: [
          _meetingAt(_utc(8, 0, day: 11)),
          _meetingAt(_utc(8, 30, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], _utc(8, 0, day: 11),
          reason: 'FR-2\'s upper bound caps the curve value');
      expect(result.instantAnchoredDays, contains(window[0]),
          reason: 'the capped value comes from a real hardFloor');
    });
  });

  group('Offsets with half and three-quarter hours (T-125)', () {
    // Every offset in the suite so far was a whole hour (`Duration.zero`,
    // 1/2/5/9 h). The bug class "someone computes with `offset.inHours`
    // instead of `offset`" is therefore visible in **no** test - checked
    // across all fourteen scheduling test files.
    //
    // Even the CI time zone matrix doesn't catch it, despite including St.
    // John's, Chatham and Lord Howe: the matrix sets the test machine's
    // zone, while the domain layer receives the offset as an explicit
    // parameter (FR-2 "Testability"). The matrix and the unit test thus
    // cover different things and don't substitute for each other.

    test('Lord Howe: a half-hour transition, same digits in the new zone', () {
      // +11:00 -> +10:30. The value reads as 07:00 on Apr 5 under +11; what's
      // sought is the instant that gives the same digits under +10:30.
      final result = reinterpretForNewOffset(
        value: DateTime.utc(2026, 4, 4, 20, 0),
        oldOffset: const Duration(hours: 11),
        newOffset: const Duration(hours: 10, minutes: 30),
      );

      expect(result, DateTime.utc(2026, 4, 4, 20, 30));
    });

    test('Chatham +12:45: the drift lands on a different UTC date', () {
      // Local reading 11:15Z + 12:45 = Mar 11, 00:00; the day to plan is the
      // next one, so locally Mar 12; target 06:30, distance 6:30 > 30min ->
      // a step of 30min -> locally Mar 12, 00:30 -> instant 11:45Z on Mar 11.
      final result = applyGapDayDrift(
        v: DateTime.utc(2026, 3, 10, 11, 15),
        preferredWakeUpTime: const TimeOfDay(hour: 6, minute: 30),
        maxDailyDelta: const Duration(minutes: 30),
        deviceUtcOffset: const Duration(hours: 12, minutes: 45),
      );

      expect(result, DateTime.utc(2026, 3, 11, 11, 45));
    });

    test('Chatham +12:45: cold start places the value on the previous UTC day',
        () {
      final result = coldStart(
        days: [DateTime.utc(2026, 4, 5)],
        preferredWakeUpTime: const TimeOfDay(hour: 0, minute: 15),
        deviceUtcOffset: const Duration(hours: 12, minutes: 45),
      );

      expect(
          result[DateTime.utc(2026, 4, 5)], DateTime.utc(2026, 4, 4, 11, 30));
    });
  });

  group('FR-2 as an invariant over a full week of appointments (T-126)', () {
    // FR-2 is a universal statement, not an example:
    //
    //   "`hardFloor` is an **upper bound** ('no later than'). The planned
    //    value may be earlier (always allowed), but **never later** (a later
    //    value means missing a real appointment)."
    //
    // It's therefore checked here as an invariant, not as a list of
    // hand-computed individual values: such a list gets adjusted on every
    // legitimate curve change anyway, the invariant does not. On record:
    // FR-2's capping can currently be deleted outright without a single
    // existing test turning red.

    test('no day is woken later than its own hardFloor', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 11 + i));
      final events = [
        _meetingAt(_utc(9, 0, day: 11)),
        _meetingAt(_utc(8, 30, day: 12)),
        _meetingAt(_utc(12, 0, day: 13)),
        _meetingAt(_utc(6, 0, day: 14)),
        _meetingAt(_utc(10, 0, day: 15)),
        _meetingAt(_utc(5, 30, day: 16)),
        _meetingAt(_utc(9, 0, day: 17)),
      ];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(8, 0, day: 10),
        allEvents: events,
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      for (final day in window) {
        final value = result.valuesByDay[day];
        final floor = hardFloor(
          day: day,
          allEvents: events,
          deviceUtcOffset: Duration.zero,
          durationToWakeUp: Duration.zero,
          durationToGetReady: Duration.zero,
        );
        expect(value, isNotNull,
            reason: 'every day has a real appointment - none may be empty');
        expect(value!.isAfter(floor!), isFalse,
            reason: 'FR-2: never later than its own hardFloor '
                '(${isoDate(day)}: value $value, upper bound $floor)');
      }
    });
  });

  group('FR-2: a hardFloor only pulls EARLIER, never later (T-132)', () {
    // Device report from 2026-09-11, a real calendar: the wake time ran
    // from 06:45 through 08:00 to 11:00 - "significantly more than drift,
    // and more than needed, and not even close to the preferred time".
    //
    // FR-2 is unambiguous about this:
    //
    //   "`hardFloor` is an **upper bound** ("no later than"). The planned
    //    value may be earlier (ALWAYS ALLOWED), but never later (a later
    //    value means missing a real appointment)."
    //
    // and FR-5 says the same thing again from the other side:
    //
    //   "`hardFloor` is exclusively an upper bound (FR-2), NEVER A
    //    DIRECTIONAL REQUIREMENT."
    //
    // Someone who gets up at 06:45 has long since satisfied an appointment
    // at 11:00. There's no reason to sleep in for it - and certainly none
    // to blow `maxDailyDelta` for it. Toward later, the wake time is moved
    // exclusively by `preferredWakeUpTime` (FR-4), bounded by
    // `maxDailyDelta`.

    test('two later appointments do not pull the wake time up', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 45, day: 11),
        allEvents: [
          _meetingAt(_utc(8, 0, day: 12)),
          _meetingAt(_utc(11, 0, day: 13)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      // FR-4: 06:45 -> 07:00 is a step of 15min, within the bound, and
      // preferredWakeUpTime is reached exactly (no overshoot).
      expect(result.valuesByDay[window[0]], _utc(7, 0, day: 12));
      // Then holds - the 11 o'clock appointment demands nothing.
      expect(result.valuesByDay[window[1]], _utc(7, 0, day: 13));
      for (final day in window) {
        expect(result.valuesByDay[day], isNotNull);
        expect(result.valuesByDay[day]!.hour, lessThanOrEqualTo(7),
            reason: 'no day may move later than the preferredWakeUpTime');
      }
    });

    test('a single later appointment does not consume the free days before it',
        () {
      // The second part of the report ("reacts extremely to free days"):
      // the days before a late appointment were used as a ramp to climb up
      // toward it - 07:48, 08:52, 09:56, 11:00.
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 45, day: 11),
        allEvents: [_meetingAt(_utc(11, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      for (final day in window) {
        expect(result.valuesByDay[day], _utc(7, 0, day: day.day),
            reason: 'every day rests on the preferredWakeUpTime');
      }
    });

    test('smoothing toward EARLIER still works as before - unchanged', () {
      // Counter-check, and the actual purpose of FR-5/FR-6: an appointment
      // that lies earlier than the current wake time is binding, and the
      // path there is spread over the days instead of dumped onto one
      // night.
      final window = List.generate(7, (i) => _utc(0, 0, day: 12 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 11),
        allEvents: [_meetingAt(_utc(5, 0, day: 15))],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 30, day: 12));
      expect(result.valuesByDay[window[1]], _utc(6, 0, day: 13));
      expect(result.valuesByDay[window[2]], _utc(5, 30, day: 14));
      expect(result.valuesByDay[window[3]], _utc(5, 0, day: 15));
    });
  });

  group('FR-6: capping at an appointment must be reported too (T-133)', () {
    // FR-6: "On EVERY excess over `maxDailyDelta` (`N=1` or distributed) the
    // user is notified once."
    //
    // T-105 fixed this for the branch with no following points. The second
    // path, where a day's value is capped by an appointment - capping a
    // running curve value at its own `hardFloor` - still reports nothing.
    // The original review had noted it as a weaker side finding, because the
    // notification happened to fire in its own probe anyway (a following day
    // started a new run).
    //
    // It surfaced from a worked everyday case: the wake time has drifted
    // over an appointment-free weekend toward `preferredWakeUpTime`, then
    // work is entered into the calendar late. Monday gets capped to its
    // `hardFloor` - a step of 45 minutes against an allowed 30, and the user
    // never hears about it.

    test('a capping jump over maxDailyDelta is reported', () {
      final window = List.generate(7, (i) => _utc(0, 0, day: 14 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0, day: 13),
        allEvents: [
          _meetingAt(_utc(6, 15, day: 14)),
          _meetingAt(_utc(6, 15, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 15, day: 14),
          reason:
              'FR-2: the appointment caps the value - that part is correct');
      expect(result.overrunNotificationNeeded, isTrue,
          reason:
              '45 minutes against an allowed 30 - FR-6 requires the report');
    });

    test('a cap within the bound does not report', () {
      // Counter-check against over-correction.
      final window = List.generate(7, (i) => _utc(0, 0, day: 14 + i));

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(6, 40, day: 13),
        allEvents: [
          _meetingAt(_utc(6, 15, day: 14)),
          _meetingAt(_utc(6, 15, day: 15)),
        ],
        deviceUtcOffset: Duration.zero,
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay[window[0]], _utc(6, 15, day: 14));
      expect(result.overrunNotificationNeeded, isFalse,
          reason: '25 minutes lies within the bound');
    });
  });
}
