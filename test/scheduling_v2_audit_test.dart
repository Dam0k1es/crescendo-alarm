import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

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
  group('FR-5 step 2: a ΔT=0 point (T-104, revised by T-139)', () {
    // T-104 (2026-09-11) read the spec sentence "a point with ΔT=0 ... is
    // never grouped with a following point" without a positional caveat and
    // cut the candidates at the first ΔT=0 point wherever it sat. That cut
    // also cut off FR-7's lookahead (docs/TODO.md T-139): an already-reached
    // point hid a later, earlier one, and the run toward it started too late
    // - two steps of twice maxDailyDelta in the spec's own FR-7 example.
    //
    // Maintainer decision, 2026-10-05: the smooth week of that example is the
    // intended behaviour. FR-5 step 2 now says what remains of the rule: a
    // ΔT=0 point is never grouped with a following LATER point (step 1's
    // violation check already guarantees that - the curve would rise above
    // the point's own hardFloor), but a following EARLIER point is grouped
    // through it.

    test('ΔT=0 at position 2 no longer hides the earlier point behind it', () {
      // T-104's own evidence case. It used to require t2; under the decision
      // the farthest non-violating point t3 is the target - the curve
      // 07:00 -> 05:00 passes t1 (08:00) and t2 (07:00) below both.
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(8, 0, day: 2)),
          HardFloorPoint(dayOffset: 2, value: _utc(7, 0, day: 3)), // ΔT = 0
          HardFloorPoint(dayOffset: 3, value: _utc(5, 0, day: 4)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
        offsetAt: fixedOffset(Duration.zero),
      );

      expect(result.dayOffset, 3);
      expect(result.value, _utc(5, 0, day: 4));
    });

    test('the same case over the whole week: no step above maxDailyDelta', () {
      // What the plan actually does with it. FR-7 still starts the run as
      // late as possible, so the week is the same as under T-104's cut:
      // 07:00, 06:00, 05:00 - steps 0, 60, 60 against an allowed 60.
      final window = [for (var d = 2; d <= 4; d++) _utc(0, 0, day: d)];
      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(7, 0),
        allEvents: [
          _meetingAt(_utc(8, 0, day: 2)),
          _meetingAt(_utc(7, 0, day: 3)),
          _meetingAt(_utc(5, 0, day: 4)),
        ],
        offsetAt: fixedOffset(Duration.zero),
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay.values.toList(),
          [_utc(7, 0, day: 2), _utc(6, 0, day: 3), _utc(5, 0, day: 4)]);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test('the spec\'s own case (ΔT=0 at position 1) stays unchanged', () {
      final result = groupTarget(
        anchor: _utc(7, 0),
        points: [
          HardFloorPoint(dayOffset: 1, value: _utc(7, 0, day: 2)), // ΔT = 0
          HardFloorPoint(dayOffset: 4, value: _utc(9, 0, day: 5)),
        ],
        maxDailyDelta: const Duration(minutes: 60),
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
      );

      // -11:59 wins against +12:01, so backward, capped at 30min.
      expect(result, _utc(18, 29, day: 2));
    });

    test('a distance of 12:01 is read as "later"', () {
      final result = applyGapDayDrift(
        v: _utc(19, 1, day: 1),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        offsetAt: fixedOffset(Duration.zero),
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
    // FR-2 (reworded by docs/TODO.md T-206): "The device zone's rules at the
    // appointment's own instant - never the appointment's own zone, and not
    // the offset in effect at the moment of evaluation - decide which
    // calendar day the instant is assigned to: the calendar date the
    // device's clock shows at that instant (L, FR-1)."
    //
    // At a CONSTANT offset this is unambiguously decided - and the two
    // wordings agree there, which is what these cases pin down. The existing FR-2
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
        offsetAt: fixedOffset(offset),
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
          offsetAt: fixedOffset(offset),
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
          offsetAt: fixedOffset(offset),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(const Duration(hours: 12, minutes: 45)),
      );

      expect(result, DateTime.utc(2026, 3, 11, 11, 45));
    });

    test('Chatham +12:45: cold start places the value on the previous UTC day',
        () {
      final result = coldStart(
        days: [DateTime.utc(2026, 4, 5)],
        preferredWakeUpTime: const TimeOfDay(hour: 0, minute: 15),
        offsetAt: fixedOffset(const Duration(hours: 12, minutes: 45)),
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
        offsetAt: fixedOffset(Duration.zero),
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
          offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
      // The precondition's bullet 1 says "every day 07:00 ... NO overrun
      // notification" - both halves asserted, every day exactly.
      for (final day in window) {
        expect(result.valuesByDay[day], _utc(7, 0, day: day.day));
      }
      expect(result.overrunNotificationNeeded, isFalse);
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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

  group('FR-7: an already-reached point must not end the lookahead (T-139)',
      () {
    // The diagnostics log that found T-139 (preferredWakeUpTime 09:00,
    // maxDailyDelta 90min, 30min lead time; earliest appointments 05:00,
    // 08:00, 12:00, 10:00, 08:00, 05:00, 05:00 from Thursday on), anchored on
    // its own Thursday's 04:30. The engine planned Sun 09:00 -> Mon 06:45 ->
    // Tue 04:30, two steps of 2:15 against an allowed 1:30, and notified: on
    // Sunday Monday's 07:30 had ΔT=0 and hid Tuesday. The rule-compliant plan
    // the TODO entry names holds Sunday at 07:30.
    test('the reported week: Sunday held at 07:30, every step within 90min',
        () {
      final window = [for (var d = 16; d <= 22; d++) _utc(0, 0, day: d)];
      final result = computeWeekPlan(
        window: window, // Fri 16 .. Thu 22
        lastEffectiveWakeTime: _utc(4, 30, day: 15), // Thu
        allEvents: [
          _meetingAt(_utc(8, 0, day: 16)),
          _meetingAt(_utc(12, 0, day: 17)),
          _meetingAt(_utc(10, 0, day: 18)),
          _meetingAt(_utc(8, 0, day: 19)),
          _meetingAt(_utc(5, 0, day: 20)),
          _meetingAt(_utc(5, 0, day: 21)),
        ],
        offsetAt: fixedOffset(Duration.zero),
        durationToWakeUp: const Duration(minutes: 30),
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 9, minute: 0),
        maxDailyDelta: const Duration(minutes: 90),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay.values.toList(), [
        _utc(6, 0, day: 16), // Fri
        _utc(7, 30, day: 17), // Sat
        _utc(7, 30, day: 18), // Sun - not 09:00
        _utc(6, 0, day: 19), // Mon
        _utc(4, 30, day: 20), // Tue
        _utc(4, 30, day: 21), // Wed
        _utc(6, 0, day: 22), // Thu
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group('FR-7: a drift must leave every nearer point reachable (T-139)', () {
    // Found by test/scheduling_v2_smoothness_property_test.dart (its case
    // 360, here at UTC+0). FR-7's feasibility was checked against F alone -
    // the farthest point a smooth curve reaches. Anchor 05:04,
    // preferredWakeUpTime 06:30, maxDailyDelta 60, hardFloors 04:36 (day 2)
    // and 03:42 (day 3): the drift to 05:42 still reached F (120min over two
    // days), but left 66 minutes into day 2's 04:36. The drift is now capped
    // where every point stays reachable: 05:36 (32 minutes; day 2 needs
    // 05:36 - 04:36 = 60).
    test('the drift stops where the nearer, stricter point is still reachable',
        () {
      final window = [for (var d = 2; d <= 8; d++) _utc(0, 0, day: d)];
      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(5, 4),
        allEvents: [
          _meetingAt(_utc(4, 36, day: 3)),
          _meetingAt(_utc(3, 42, day: 4)),
        ],
        offsetAt: fixedOffset(Duration.zero),
        durationToWakeUp: Duration.zero,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: const TimeOfDay(hour: 6, minute: 30),
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );

      expect(result.valuesByDay.values.toList(), [
        _utc(5, 36, day: 2),
        _utc(4, 36, day: 3), // its own hardFloor, 60 minutes down
        _utc(3, 42, day: 4),
        _utc(4, 42, day: 5), // FR-4 drifts back toward 06:30
        _utc(5, 42, day: 6),
        _utc(6, 30, day: 7),
        _utc(6, 30, day: 8),
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group('FR-7: reachability is checked in groupTarget\'s frame (T-139 review)',
      () {
    // The first version of T-139's fix (b) measured "is every point still
    // reachable?" on readings with FR-1's 12-hour wrap, while groupTarget's
    // violation check places the curve at the anchor reading's date + the
    // point's offset and compares instants. Where the anchor's reading lies
    // on the date BEFORE its day - a night shift: the alarm for a 00:00
    // shift rings at 22:00 the evening before (T-118b) - the two disagree by
    // a day: a daytime appointment two days on read as "11 hours earlier,
    // one day left", nothing was feasible, and the run started at once. FR-7
    // says a run starts as late as possible; these days lost up to 35
    // minutes of sleep for no gain at all (Günther's review, differential
    // case #22).

    test('differential case #22: the evening anchor is held, not pulled '
        'earlier', () {
      final window = [
        for (var d = 30; d <= 36; d++) DateTime.utc(2027, 10, d)
      ];
      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: DateTime.utc(2027, 10, 28, 18, 23),
        allEvents: [
          _meetingAt(DateTime.utc(2027, 10, 31, 12, 16)),
          _meetingAt(DateTime.utc(2027, 11, 5, 16, 24)),
        ],
        offsetAt: fixedOffset(Duration.zero),
        durationToWakeUp: const Duration(minutes: 120),
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 90),
        gapDayCounter: 1,
        scheduleOnGapDays: false,
      );
      // scheduleOnGapDays off: only the two appointment days carry a value.
      // Oct 31 holds 18:23 (on the 30th - the anchor's frame), as the
      // pure layer before T-139 did; not 17:48.
      expect(result.valuesByDay[DateTime.utc(2027, 10, 31)],
          DateTime.utc(2027, 10, 30, 18, 23));
    });

    test('a night-shift week: 22:00 the evening before is held all week', () {
      // Shift at 00:00 on Jan 10, two hours to wake up -> the anchor rang
      // at 22:00 on Jan 9. A daytime appointment at 13:00 on Jan 12 (wake
      // 11:00) and one at 23:00 on Jan 17 (wake 21:00). Every day's 22:00
      // the evening before lies long before both; nothing has to move.
      final window = [for (var d = 11; d <= 17; d++) _utc(0, 0, day: d)];
      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: _utc(22, 0, day: 9),
        allEvents: [
          _meetingAt(_utc(13, 0, day: 12)),
          _meetingAt(_utc(23, 0, day: 17)),
        ],
        offsetAt: fixedOffset(Duration.zero),
        durationToWakeUp: const Duration(hours: 2),
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: null,
        maxDailyDelta: const Duration(minutes: 60),
        gapDayCounter: 0,
        scheduleOnGapDays: true,
      );
      expect(result.valuesByDay.values.toList(),
          [for (var d = 10; d <= 16; d++) _utc(22, 0, day: d)]);
      expect(result.overrunNotificationNeeded, isFalse);
    });
  });

  group('FR-7: a run starts only for a point it can aim at (T-139 review B1)',
      () {
    // Second review, blocking: holding was vetoed by a point that FR-1 reads
    // as LATER (it lies more than 12 hours earlier by the clock, so the
    // 12-hour wrap turns it round), while the run's target F still came from
    // FR-1's wrapped ΔT and was a different, nearer point. The run then did
    // nothing for the vetoing point and suppressed the FR-4 drift that would
    // have helped. A night-to-day shift change - Marie's case
    // (docs/personas.md).
    //
    // Night to day, UTC: anchor 21:46, appointments 19:04 (day 3) and 07:43
    // (day 5), maxDailyDelta 90, preferredWakeUpTime 14:27. The first
    // version planned 21:05, 20:25, 19:44, 18:14, 12:58, 07:43 - two steps
    // of 316 minutes. The drift toward 14:27 is feasible for 19:04 and is the
    // plan: 20:16, 18:46. From 18:46 on, 07:43 is within 12 hours and reads
    // EARLIER - now it is a target, and the run spreads what is left of the
    // 14-hour change evenly: 16:00:15, 13:14:30, 10:28:45, 07:43 (165:45 a day -
    // more than maxDailyDelta, unavoidable, and reported: no curve can cover
    // 14 hours in six days at 90 minutes). This is also the pure layer's plan
    // before T-139 (differential case #49).
    WeekPlanResult nightToDay(TimeOfDay? preferred) => computeWeekPlan(
          window: [for (var d = 2; d <= 8; d++) _utc(0, 0, day: d)],
          lastEffectiveWakeTime: _utc(21, 46, day: 1),
          allEvents: [
            _meetingAt(_utc(19, 4, day: 5)),
            _meetingAt(_utc(7, 43, day: 7)),
          ],
          offsetAt: fixedOffset(Duration.zero),
          durationToWakeUp: Duration.zero,
          durationToGetReadyForDay: (_) => Duration.zero,
          preferredWakeUpTime: preferred,
          maxDailyDelta: const Duration(minutes: 90),
          gapDayCounter: 0,
          scheduleOnGapDays: true,
        );

    test('with a preferredWakeUpTime: FR-4 drifts until 07:43 is in reach',
        () {
      final result = nightToDay(const TimeOfDay(hour: 14, minute: 27));
      expect(result.valuesByDay.values.take(6).toList(), [
        _utc(20, 16, day: 2),
        _utc(18, 46, day: 3),
        DateTime.utc(2026, 1, 4, 16, 0, 15),
        DateTime.utc(2026, 1, 5, 13, 14, 30),
        DateTime.utc(2026, 1, 6, 10, 28, 45),
        _utc(7, 43, day: 7),
      ]);
      expect(result.overrunNotificationNeeded, isTrue);
    });

    test('without one: the anchor is held until 19:04 needs it', () {
      // 21:46 -> 19:04 is 162 minutes over three days; holding two days and
      // stepping 90 + 72 (FR-7's run of N=2 from day 2) is as late as it
      // gets - not 41-81 minutes earlier on days 0-1.
      final result = nightToDay(null);
      expect(result.valuesByDay[_utc(0, 0, day: 2)], _utc(21, 46, day: 2));
      expect(result.valuesByDay[_utc(0, 0, day: 3)], _utc(21, 46, day: 3));
    });
  });

  group('FR-1: ΔT at full resolution (T-139 review)', () {
    // The time of day ΔT is taken from dropped the milliseconds (hour,
    // minute, second and only the microsecond FIELD, 0-999), so a value
    // carrying milliseconds - every value FR-7's bisection produces - was
    // misread by up to 999 ms: a drift to the preferred time then landed
    // 0.999 s past it and stayed there. Found by the property test's
    // full-resolution comparison.
    test('milliseconds count', () {
      expect(
          readingDelta(DateTime.utc(2026, 1, 1, 7, 0, 0, 0),
              DateTime.utc(2026, 1, 2, 7, 0, 0, 500)),
          const Duration(milliseconds: 500));
    });

    test('a drift from a value with milliseconds lands exactly on the '
        'preferred time', () {
      final v = applyGapDayDrift(
        v: DateTime.utc(2026, 1, 1, 6, 59, 44, 999, 999),
        preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
        maxDailyDelta: const Duration(minutes: 30),
        offsetAt: fixedOffset(Duration.zero),
      );
      expect(v, DateTime.utc(2026, 1, 2, 7, 0));
    });
  });

  group('FR-1/FR-5/FR-7: an evening appointment on the same date is no '
      'target (T-208 shape)', () {
    // Re-audit 2026-10-06 (maintainer: "Behebe FR-7"). Once the wake time
    // lies more than 12 hours before an evening appointment, FR-1's wrap read
    // that appointment as "earlier" and FR-5 aimed a run at it, while FR-2
    // bounds a day only by ITS OWN hardFloor, and a morning value on the same
    // date already lies before an evening one. Without the evening
    // appointment each plan is smooth.
    WeekPlanResult plan(DateTime anchor, List<DateTime> appointments,
            {required int md, TimeOfDay? preferred}) =>
        computeWeekPlan(
          window: [
            for (var d = 1; d <= 7; d++)
              DateTime.utc(anchor.year, anchor.month, anchor.day + d)
          ],
          lastEffectiveWakeTime: anchor,
          allEvents: [for (final a in appointments) _meetingAt(a)],
          offsetAt: fixedOffset(Duration.zero),
          durationToWakeUp: Duration.zero,
          durationToGetReadyForDay: (_) => Duration.zero,
          preferredWakeUpTime: preferred,
          maxDailyDelta: Duration(minutes: md),
          gapDayCounter: 0,
          scheduleOnGapDays: true,
        );

    void expectSteps(WeekPlanResult result, DateTime anchor, int md) {
      var previous = anchor;
      for (final value in result.valuesByDay.values) {
        final step = readingDelta(previous, value!).abs();
        expect(step, lessThanOrEqualTo(Duration(minutes: md)),
            reason: 'step into $value: $step (plan '
                '${result.valuesByDay.values.toList()})');
        previous = value;
      }
      expect(result.overrunNotificationNeeded, isFalse);
    }

    test('Sun 07:00, Wed 05:30, Fri 19:00, md 30: 06:30, 06:00, 05:30, hold',
        () {
      // 2026-01-04 is a Sunday.
      final result = plan(_utc(7, 0, day: 4),
          [_utc(5, 30, day: 7), _utc(19, 0, day: 9)],
          md: 30);
      expect(result.valuesByDay.values.toList(), [
        _utc(6, 30, day: 5),
        _utc(6, 0, day: 6),
        _utc(5, 30, day: 7),
        _utc(5, 30, day: 8),
        _utc(5, 30, day: 9), // Friday: 05:30 is before its 19:00
        _utc(5, 30, day: 10),
        _utc(5, 30, day: 11),
      ]);
      expect(result.overrunNotificationNeeded, isFalse);
    });

    test('anchor 09:30, 04:20 (+6) and 20:30 (+7), md 73: smooth', () {
      final anchor = _utc(9, 30, day: 4);
      final result =
          plan(anchor, [_utc(4, 20, day: 10), _utc(20, 30, day: 11)], md: 73);
      expectSteps(result, anchor, 73);
      expect(result.valuesByDay[_utc(0, 0, day: 10)], _utc(4, 20, day: 10));
    });

    test('P 07:00, 05:00 (+3) and 18:30 (+6), md 30: the even run, no jump',
        () {
      // 07:00 -> 05:00 in three days needs 40 minutes a day - an overrun
      // FR-6 spreads evenly and reports. What must not happen is a second,
      // avoidable jump toward 18:30 "earlier" (it planned 06:20, 03:58).
      final anchor = _utc(7, 0, day: 4);
      final result = plan(anchor, [_utc(5, 0, day: 7), _utc(18, 30, day: 10)],
          md: 30, preferred: const TimeOfDay(hour: 7, minute: 0));
      expect(result.valuesByDay.values.toList(), [
        _utc(6, 20, day: 5),
        _utc(5, 40, day: 6),
        _utc(5, 0, day: 7),
        _utc(5, 30, day: 8), // FR-4 drifts back toward 07:00
        _utc(6, 0, day: 9),
        _utc(6, 30, day: 10), // before Saturday's 18:30
        _utc(7, 0, day: 11),
      ]);
      expect(result.overrunNotificationNeeded, isTrue);
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
        offsetAt: fixedOffset(Duration.zero),
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
        offsetAt: fixedOffset(Duration.zero),
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
