import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

// docs/TODO.md T-223 (maintainer decision 2026-10-27, "Glätten + Hinweis"):
// FR-10's cold start - no lastEffectiveWakeTime, a fresh install or after data
// loss - follows the rules of normal planning when a `preferredWakeUpTime` is
// set: that time is the anchor, the way to the first real hardFloor is smoothed
// by FR-5/FR-7 (never more than `maxDailyDelta` a day unless the days run
// out), and a jump that cannot be spread is reported by FR-6. Without a
// `preferredWakeUpTime` nothing is invented (FR-10 unchanged).

DateTime _utc(int hour, int minute, {int day = 1}) =>
    DateTime.utc(2026, 1, day, hour, minute);

Meeting _at(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

WeekPlanResult _plan(
  List<DateTime> window,
  List<Meeting> events, {
  TimeOfDay? preferred = const TimeOfDay(hour: 7, minute: 0),
  Duration maxDelta = const Duration(minutes: 30),
}) =>
    computeWeekPlan(
      window: window,
      lastEffectiveWakeTime: null,
      allEvents: events,
      offsetAt: fixedOffset(Duration.zero),
      durationToWakeUp: Duration.zero,
      durationToGetReadyForDay: (_) => Duration.zero,
      preferredWakeUpTime: preferred,
      maxDailyDelta: maxDelta,
      gapDayCounter: 0,
      scheduleOnGapDays: true,
    );

void main() {
  final window = List.generate(7, (i) => _utc(0, 0, day: 1 + i));

  test('an earlier first appointment is approached in steps, not in one jump',
      () {
    // preferred 07:00, first appointment 05:00 on day 5: two hours down, at
    // most 30 minutes a day, so the run has to start early enough.
    final result = _plan(window, [_at(_utc(5, 0, day: 5))]);

    DateTime v(int i) => result.valuesByDay[window[i]]!;
    int minuteOfDay(DateTime d) => d.hour * 60 + d.minute;
    for (var i = 1; i < 5; i++) {
      final step = minuteOfDay(v(i - 1)) - minuteOfDay(v(i));
      expect(step <= 30, isTrue, reason: 'day ${i + 1} moved by $step min');
    }
    expect(v(4), _utc(5, 0, day: 5));
    expect(result.overrunNotificationNeeded, isFalse);
  });

  test('an earlier appointment on day 1 is a jump that has to be reported', () {
    // Nothing to spread it over: 07:00 -> 04:00 in one day, 180 > 30 minutes.
    final result = _plan(window, [_at(_utc(4, 0, day: 1))]);

    expect(result.valuesByDay[window[0]], _utc(4, 0, day: 1));
    expect(result.overrunNotificationNeeded, isTrue);
  });

  test('a LATER first appointment does not pull the wake time later', () {
    // preferred 07:00, appointment 11:00 on day 4: hardFloor is an upper
    // bound, a cap and not a target (FR-5 precondition, T-132).
    final result = _plan(window, [_at(_utc(11, 0, day: 4))]);

    for (var i = 0; i < 4; i++) {
      expect(result.valuesByDay[window[i]], _utc(7, 0, day: 1 + i),
          reason: 'day ${i + 1}');
    }
    expect(result.overrunNotificationNeeded, isFalse);
  });

  test('no appointment at all still keeps the preferred time every day', () {
    final result = _plan(window, const []);

    for (var i = 0; i < 7; i++) {
      expect(result.valuesByDay[window[i]], _utc(7, 0, day: 1 + i));
    }
    expect(result.overrunNotificationNeeded, isFalse);
  });

  test(
      'without a preferred time nothing is invented before the first '
      'appointment (FR-10 unchanged)', () {
    final result = _plan(window, [_at(_utc(5, 30, day: 6))], preferred: null);

    for (var i = 0; i < 5; i++) {
      expect(result.valuesByDay[window[i]], isNull, reason: 'day ${i + 1}');
    }
    expect(result.valuesByDay[window[5]], _utc(5, 30, day: 6));
    expect(result.overrunNotificationNeeded, isFalse);
  });
}
