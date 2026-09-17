import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// docs/TODO.md T-76: computeWeekPlan derived its HardFloorPoints' dayOffsets
// via `window[j].difference(anchorDay).inDays`. On locally-tagged window
// markers, this counts one day too few across a daylight-saving transition -
// two window days get the same offset. Consequence: N_remaining too small,
// the curve too steep, and `groupTarget`'s violation check compares the
// wrong day against its hardFloor.
//
// Why `tz.TZDateTime` as the window marker: in production, replan() builds
// the window from locally-tagged midnight markers; on the dev machine
// (UTC+0), though, those behave like UTC and the bug stays invisible.
// `tz.TZDateTime` is a `DateTime` with real transition behaviour and makes
// the test independent of the test machine's time zone - exactly the gap the
// first fix (T-74d) missed.

const cest = Duration(hours: 2);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('T-76: the curve uses the real calendar day distance across the transition',
      () {
    final berlin = tz.getLocation('Europe/Berlin');
    // Window 2026-03-28 .. 2026-04-03; the transition falls on 2026-03-29.
    final window =
        List.generate(7, (i) => tz.TZDateTime(berlin, 2026, 3, 28 + i));

    // The anchor conceptually belongs to 2026-03-27 (the day before the
    // window): 05:00 UTC = 07:00 Berlin.
    final anchor = DateTime.utc(2026, 3, 27, 5, 0);

    // A single real appointment, on the last window day: 05:10 UTC = 07:10
    // Berlin on 2026-04-03. With 30min to wake up + 2h to get ready, that
    // gives a hardFloor of 02:40 UTC = 04:40 Berlin, i.e. ΔT = -140 min
    // relative to the anchor.
    final event = Meeting(
      from: tz.TZDateTime.from(DateTime.utc(2026, 4, 3, 5, 10), berlin),
      to: tz.TZDateTime.from(DateTime.utc(2026, 4, 3, 6, 10), berlin),
      isAllDay: false,
      startTimeZone: 'Europe/Berlin',
      endTimeZone: 'Europe/Berlin',
    );

    final result = computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: anchor,
      allEvents: [event],
      deviceUtcOffset: cest,
      durationToWakeUp: const Duration(minutes: 30),
      durationToGetReady: const Duration(hours: 2),
      preferredWakeUpTime: null,
      maxDailyDelta: const Duration(minutes: 20),
      gapDayCounter: 0,
    );

    // From the anchor (Mar 27) to the target (Apr 3) is 7 calendar days.
    // Simply holding is infeasible (140/6 = 23.3 min > 20 min), so today is
    // day 1 of a 7-day run: the step is 140/7 = exactly 20 min.
    // With the bug, the target distance was counted as 6 days -> N = 6 ->
    // step 23.33 min -> 06:36:40 instead of 06:40.
    expect(
      result.valuesByDay[window[0]],
      DateTime.utc(2026, 3, 28, 4, 40),
      reason: 'expected 04:40 UTC (= 06:40 Berlin, step exactly 20 min), '
          'got ${result.valuesByDay[window[0]]}',
    );

    // And the appointment itself is hit exactly, not exceeded (FR-2).
    expect(result.valuesByDay[window[6]], DateTime.utc(2026, 4, 3, 2, 40));

    // Every window day gets exactly one value of its own - no day drops out
    // of the plan due to an offset collision.
    expect(result.valuesByDay.length, 7);
    expect(window.map(isoDate).toSet().length, 7);
  });

  test('T-76: a cold start across the transition anchors on the right day',
      () {
    final berlin = tz.getLocation('Europe/Berlin');
    final window =
        List.generate(7, (i) => tz.TZDateTime(berlin, 2026, 3, 28 + i));

    // First real appointment on 2026-03-31 (i.e. after the transition), so
    // the cold-start branch sets its anchor in the middle of the window and
    // the dayOffsets afterward get counted across the transition.
    Meeting at(int day, int utcHour, int utcMinute) => Meeting(
          from: tz.TZDateTime.from(
              DateTime.utc(2026, 3, day, utcHour, utcMinute), berlin),
          to: tz.TZDateTime.from(
              DateTime.utc(2026, 3, day, utcHour + 1, utcMinute), berlin),
          isAllDay: false,
          startTimeZone: 'Europe/Berlin',
          endTimeZone: 'Europe/Berlin',
        );

    final result = computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: null,
      allEvents: [at(31, 6, 0), at(2, 6, 0)],
      deviceUtcOffset: cest,
      durationToWakeUp: const Duration(minutes: 30),
      durationToGetReady: Duration.zero,
      preferredWakeUpTime: const TimeOfDay(hour: 7, minute: 0),
      maxDailyDelta: const Duration(minutes: 30),
      gapDayCounter: 0,
    );

    // The anchor day (Mar 31) carries its own hardFloor and is
    // instant-anchored; all seven days must have a value.
    expect(result.valuesByDay[window[3]], DateTime.utc(2026, 3, 31, 5, 30));
    expect(result.instantAnchoredDays.contains(window[3]), isTrue);
    expect(result.valuesByDay.length, 7);
  });
}
