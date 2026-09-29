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

// Ids used below - tests T01 ..., requirements T206-R1 ..., and "requirements"
// section numbers such as b.0 or 8.2 - are defined in
// docs/t206-dst-requirements.md (not docs/TODO.md items: T33 is not T-33).

// docs/TODO.md T-206: daylight saving within one zone - the DERIVED pure
// cases of the requirements' test table (T03, T14, T22, T25, T28, T40-T42,
// T45, T46, T51-T53, the P1/P2 invariants). The spec's own verbatim "Test:"
// bullets are in test/scheduling_v2_test.dart; replan()/Checkpoint 2 cases
// in test/replan_dst_test.dart.
//
// Every instant inside a gap or an overlap is a literal from the Python
// `zoneinfo` computation (requirements section 8), never re-derived by the
// resolver under test. Zone rules are injected (`zoneRules`), so these run
// identically in every CI leg - except T03's process-zone half, which checks
// the PROCESS zone's own transitions and skips where there are none.

import 'dart:math';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/models/scheduling/stored_values.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/local_zone_transitions.dart';
import 'support/t206_plan_cases.dart';
import 'support/zone_rules.dart';

late tz.Location _berlin;
late ZoneOffsetAt _berlinRules;

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
  bool scheduleOnGapDays = true,
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
      scheduleOnGapDays: scheduleOnGapDays,
    );

/// Asserts plan [a] (injected zone rules) and plan [b] (a constant offset)
/// agree in everything the result carries; returns the mismatches.
List<String> _differences(
    WeekPlanResult a, WeekPlanResult b, List<DateTime> window, String label) {
  final out = <String>[];
  for (final day in window) {
    if (a.valuesByDay[day]?.microsecondsSinceEpoch !=
        b.valuesByDay[day]?.microsecondsSinceEpoch) {
      out.add('$label: $day rules ${a.valuesByDay[day]}, fixed '
          '${b.valuesByDay[day]}');
    }
    if (a.plannedClockTimes[day] != b.plannedClockTimes[day]) {
      out.add('$label: $day clock time rules ${a.plannedClockTimes[day]}, '
          'fixed ${b.plannedClockTimes[day]}');
    }
    if (a.instantAnchoredDays.contains(day) !=
        b.instantAnchoredDays.contains(day)) {
      out.add('$label: $day anchored differs');
    }
  }
  if (a.overrunNotificationNeeded != b.overrunNotificationNeeded) {
    out.add('$label: overrun differs');
  }
  if (a.safetyValveTriggered != b.safetyValveTriggered) {
    out.add('$label: safety valve differs');
  }
  return out;
}

WeekPlanResult _planCase(PlanCase c, ZoneOffsetAt rules) => computeWeekPlan(
      window: c.window,
      lastEffectiveWakeTime: c.anchor,
      allEvents: c.events,
      offsetAt: rules,
      durationToWakeUp: c.durationToWakeUp,
      durationToGetReadyForDay: (_) => c.durationToGetReady,
      preferredWakeUpTime: c.preferredWakeUpTime,
      maxDailyDelta: c.maxDailyDelta,
      gapDayCounter: c.gapDayCounter,
      scheduleOnGapDays: c.scheduleOnGapDays,
    );

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    _berlin = tz.getLocation('Europe/Berlin');
    _berlinRules = zoneRules(_berlin);
  });

  group('T03: resolveWallClock is TZ-1\'s R (T206-R2)', () {
    test('injected Berlin rules: skipped, repeated and ordinary readings', () {
      // 29 Mar 02:30 is skipped -> the transition, 01:00Z (03:00 CEST).
      expect(resolveWallClock(wall(2026, 3, 29, 2, 30), _berlinRules),
          DateTime.utc(2026, 3, 29, 1, 0));
      expect(resolveWallClock(wall(2026, 3, 28, 2, 30), _berlinRules),
          DateTime.utc(2026, 3, 28, 1, 30));
      // 25 Oct 02:30 is repeated -> the later occurrence, 01:30Z (CET).
      expect(resolveWallClock(wall(2026, 10, 25, 2, 30), _berlinRules),
          DateTime.utc(2026, 10, 25, 1, 30));
      expect(resolveWallClock(wall(2026, 10, 24, 2, 30), _berlinRules),
          DateTime.utc(2026, 10, 24, 0, 30));
    });

    test('microsecond resolution; a gap reading resolves to the transition '
        'itself, sub-minute digits dropped', () {
      final ordinary = resolveWallClock(
          wall(2026, 7, 1, 7, 0, 0, 0, 123), _berlinRules);
      expect(ordinary, DateTime.utc(2026, 7, 1, 5, 0, 0, 0, 123));
      expect(ordinary.isUtc, isTrue);
      expect(
          resolveWallClock(wall(2026, 3, 29, 2, 30, 0, 0, 123), _berlinRules),
          DateTime.utc(2026, 3, 29, 1, 0));
    });

    test('a local-tagged reading is a programming error (assert)', () {
      expect(() => resolveWallClock(DateTime(2026, 7, 1, 7, 0), _berlinRules),
          throwsA(isA<AssertionError>()));
    });

    final transitions = localTransitions();
    test('process zone: equals localWallClockInstant at every minute within '
        '90 minutes of each 2026/27 transition', () {
      const minute = 60 * 1000;
      for (final t in transitions) {
        for (var w = t.wallStartMs - 90 * minute;
            w < t.wallEndMs + 90 * minute;
            w += minute) {
          final f = wallFields(w);
          final expected =
              localWallClockInstant(f.year, f.month, f.day, f.hour, f.minute);
          final actual = resolveWallClock(
              DateTime.fromMillisecondsSinceEpoch(w, isUtc: true),
              deviceOffsetAt);
          expect(actual.isAtSameMomentAs(expected), isTrue,
              reason: '$t, reading $f: resolveWallClock $actual, '
                  'localWallClockInstant $expected');
        }
      }
    }, skip: transitions.isEmpty ? noTransitionReason : false);

    test('process zone: equals localWallClockInstant on 500 seeded ordinary '
        'readings', () {
      final rng = Random(206);
      for (var i = 0; i < 500; i++) {
        final day = DateTime.utc(2026, 1, 1 + rng.nextInt(730));
        final h = rng.nextInt(24), m = rng.nextInt(60);
        final expected =
            localWallClockInstant(day.year, day.month, day.day, h, m);
        final actual = resolveWallClock(
            DateTime.utc(day.year, day.month, day.day, h, m), deviceOffsetAt);
        expect(actual.isAtSameMomentAs(expected), isTrue,
            reason: 'reading $day $h:$m');
      }
    });
  });

  group('resolvePlannedClockTime: R_plan (T206-R3, TZ-2a)', () {
    test('America/Nuuk 28 Mar 2026: every skipped reading 23:00-23:59 '
        'resolves to 22:59 (-2) = 29 Mar 00:59Z; the minute before the gap is '
        'the same instant (monotone within the day)', () {
      final nuuk = zoneRules(tz.getLocation('America/Nuuk'));
      for (var m = 0; m < 60; m++) {
        expect(resolvePlannedClockTime(wall(2026, 3, 28, 23, m), nuuk),
            DateTime.utc(2026, 3, 29, 0, 59),
            reason: 'reading 23:${m.toString().padLeft(2, '0')}');
      }
      expect(resolvePlannedClockTime(wall(2026, 3, 28, 22, 59), nuuk),
          DateTime.utc(2026, 3, 29, 0, 59));
      // Counter: the first reading after the gap is plain R.
      expect(resolvePlannedClockTime(wall(2026, 3, 29, 0, 0), nuuk),
          DateTime.utc(2026, 3, 29, 1, 0));
      expect(resolvePlannedClockTime(wall(2026, 3, 29, 23, 30), nuuk),
          DateTime.utc(2026, 3, 30, 0, 30));
    });

    test('counter: Santiago\'s gap starts at 00:00 on the same date - no '
        'fallback, plain R', () {
      final santiago = zoneRules(tz.getLocation('America/Santiago'));
      expect(resolvePlannedClockTime(wall(2026, 9, 6, 0, 30), santiago),
          DateTime.utc(2026, 9, 6, 4, 0));
      expect(resolvePlannedClockTime(wall(2026, 9, 5, 23, 30), santiago),
          DateTime.utc(2026, 9, 6, 3, 30));
      expect(resolvePlannedClockTime(wall(2026, 4, 4, 23, 30), santiago),
          DateTime.utc(2026, 4, 5, 3, 30));
    });
  });

  group('stored planned clock times (T206-R11)', () {
    test('clockTimeFromStored gives a UTC-tagged reading; clockTimeToStored '
        'reverses it; null passes through', () {
      final ms = wall(2026, 3, 29, 7, 0).millisecondsSinceEpoch;
      final read = clockTimeFromStored(ms);
      expect(read, wall(2026, 3, 29, 7, 0));
      expect(read!.isUtc, isTrue);
      expect(clockTimeToStored(read), ms);
      expect(clockTimeFromStored(null), isNull);
      expect(clockTimeToStored(null), isNull);
    });
  });

  group('T22: the transition on every window position (hold, P 07:00)', () {
    for (final (label, month, changeDay, before, after) in [
      ('spring', 3, 29, 6, 5),
      ('autumn', 10, 25, 5, 6),
    ]) {
      test('$label: 07:00 by the clock on every day, for k = 0..6 and '
          'maxDailyDelta 15/30', () {
        for (var k = 0; k <= 6; k++) {
          for (final md in [15, 30]) {
            final window = _window(_berlin, 2026, month, changeDay - k);
            final result = _plan(
              window: window,
              // The day before the window, 07:00 local (before the change).
              anchor: DateTime.utc(2026, month, changeDay - k - 1, before, 0),
              rules: _berlinRules,
              preferred: const TimeOfDay(hour: 7, minute: 0),
              maxDeltaMinutes: md,
            );
            for (var i = 0; i < 7; i++) {
              final dayOfMonth = changeDay - k + i;
              final expected = DateTime.utc(
                  2026, month, dayOfMonth, dayOfMonth < changeDay ? before : after, 0);
              expect(result.valuesByDay[window[i]], expected,
                  reason: 'k $k, md $md, window day ${window[i]}');
              expect(readingOf(expected, _berlinRules),
                  wall(2026, month, dayOfMonth, 7, 0));
              expect(result.plannedClockTimes[window[i]],
                  wall(2026, month, dayOfMonth, 7, 0),
                  reason: 'k $k, md $md, clock time of ${window[i]}');
            }
            expect(result.overrunNotificationNeeded, isFalse,
                reason: 'k $k, md $md');
          }
        }
      });
    }
  });

  test('T25: P in the skipped hour (P 02:30, md 15): Sun 03:00 CEST, then '
      '02:30 CEST', () {
    final window = _window(_berlin, 2026, 3, 29);
    final result = _plan(
      window: window,
      anchor: DateTime.utc(2026, 3, 28, 1, 30), // Sat 02:30 CET
      rules: _berlinRules,
      preferred: const TimeOfDay(hour: 2, minute: 30),
      maxDeltaMinutes: 15,
    );
    expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 29, 1, 0));
    for (var i = 1; i < 7; i++) {
      expect(result.valuesByDay[window[i]], DateTime.utc(2026, 3, 29 + i, 0, 30),
          reason: '${window[i]}');
    }
    expect(result.plannedClockTimes[window[0]], wall(2026, 3, 29, 2, 30));
  });

  group('T28: a run across the autumn change is planned in readings', () {
    for (final md in [15, 30]) {
      test('md $md: 07:00 by the clock every day, no notification', () {
        final window = _window(_berlin, 2026, 10, 24);
        final result = _plan(
          window: window,
          anchor: DateTime.utc(2026, 10, 23, 5, 0), // Fri 07:00 CEST
          rules: _berlinRules,
          preferred: const TimeOfDay(hour: 7, minute: 0),
          // Tue 27 Oct 07:30 CET, 30 min to wake up -> hardFloor 07:00 CET.
          events: [_event(DateTime.utc(2026, 10, 27, 6, 30), _berlin)],
          wakeUp: const Duration(minutes: 30),
          maxDeltaMinutes: md,
        );
        expect(result.valuesByDay[window[0]], DateTime.utc(2026, 10, 24, 5, 0));
        for (var i = 1; i < 7; i++) {
          expect(result.valuesByDay[window[i]],
              DateTime.utc(2026, 10, 24 + i, 6, 0),
              reason: '${window[i]}');
        }
        expect(result.overrunNotificationNeeded, isFalse);
      });
    }
  });

  test('T42 (counter): a real overrun across the change is still reported - '
      'event Sun 05:00 CEST, md 30: exactly the hardFloor, instant-anchored, '
      'no planned clock time, notification', () {
    final window = _window(_berlin, 2026, 3, 29);
    final result = _plan(
      window: window,
      anchor: DateTime.utc(2026, 3, 28, 6, 0),
      rules: _berlinRules,
      events: [_event(DateTime.utc(2026, 3, 29, 3, 0), _berlin)],
    );
    expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 29, 3, 0));
    expect(result.instantAnchoredDays, contains(window[0]));
    expect(result.plannedClockTimes.containsKey(window[0]), isFalse);
    expect(result.overrunNotificationNeeded, isTrue);
  });

  group('T45: a stale or inconsistent planned clock time is ignored', () {
    test('inconsistent (its R_plan is not the anchor): the anchor\'s own '
        'reading L(v) = 07:30 is held', () {
      final window = _window(_berlin, 2026, 3, 29);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 3, 28, 6, 30), // 07:30 CET
        anchorClockTime: wall(2026, 3, 28, 7, 0),
        rules: _berlinRules,
      );
      expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 29, 5, 30));
      expect(result.plannedClockTimes[window[0]], wall(2026, 3, 29, 7, 30));
    });

    test('consistent in whole milliseconds (the stored precision): the '
        'clock time\'s microseconds are carried on', () {
      final window = _window(_berlin, 2026, 3, 29);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 3, 28, 6, 0),
        anchorClockTime: wall(2026, 3, 28, 7, 0, 0, 0, 999),
        rules: _berlinRules,
      );
      // Taken as consistent -> held clock time 07:00:00.000999 (were it
      // treated as inconsistent, L(v) = 07:00:00.000000 would be held).
      expect(result.valuesByDay[window[0]],
          DateTime.utc(2026, 3, 29, 5, 0, 0, 0, 999));
      expect(result.plannedClockTimes[window[0]],
          wall(2026, 3, 29, 7, 0, 0, 0, 999));
    });
  });

  test('T46: a cold start across the change is silent - P 07:00, event Tue '
      '31 Mar 07:30 CEST, 30 min to wake up', () {
    final window = _window(_berlin, 2026, 3, 28);
    final result = _plan(
      window: window,
      anchor: null,
      rules: _berlinRules,
      preferred: const TimeOfDay(hour: 7, minute: 0),
      events: [_event(DateTime.utc(2026, 3, 31, 5, 30), _berlin)],
      wakeUp: const Duration(minutes: 30),
    );
    expect(result.valuesByDay[window[0]], DateTime.utc(2026, 3, 28, 6, 0));
    for (var i = 1; i < 7; i++) {
      expect(result.valuesByDay[window[i]], DateTime.utc(2026, 3, 28 + i, 5, 0),
          reason: '${window[i]}');
    }
    expect(result.overrunNotificationNeeded, isFalse);
  });

  test('T51 (pure): scheduleOnGapDays = false masks value AND planned clock '
      'time together; appointment days keep both', () {
    final window = _window(_berlin, 2026, 3, 29);
    final result = _plan(
      window: window,
      anchor: DateTime.utc(2026, 3, 28, 6, 0),
      rules: _berlinRules,
      preferred: const TimeOfDay(hour: 7, minute: 0),
      events: [
        _event(DateTime.utc(2026, 3, 30, 5, 30), _berlin), // Mon 07:30 CEST
        _event(DateTime.utc(2026, 4, 2, 5, 30), _berlin), // Thu 07:30 CEST
      ],
      scheduleOnGapDays: false,
    );
    for (final i in [0, 2, 3, 5, 6]) {
      expect(result.valuesByDay[window[i]], isNull, reason: '${window[i]}');
      expect(result.plannedClockTimes.containsKey(window[i]), isFalse,
          reason: '${window[i]}');
    }
    for (final (i, d, m) in [(1, 30, 3), (4, 2, 4)]) {
      expect(result.valuesByDay[window[i]], DateTime.utc(2026, m, d, 5, 0),
          reason: '${window[i]}: 07:00 CEST, before the 07:30 appointment');
      expect(result.plannedClockTimes[window[i]], wall(2026, m, d, 7, 0));
      expect(result.instantAnchoredDays.contains(window[i]), isFalse);
    }
  });

  group('T52: America/Nuuk, a held 23:30 across the midnight-ending gap', () {
    for (final preferred in [null, const TimeOfDay(hour: 23, minute: 30)]) {
      test('P $preferred: 28 Mar rings 22:59 (-2) on its own date, keeps '
          'clock time 23:30; the next days 23:30 (-1)', () {
        final nuuk = zoneRules(tz.getLocation('America/Nuuk'));
        final window = _window(tz.getLocation('America/Nuuk'), 2026, 3, 28);
        final result = _plan(
          window: window,
          anchor: DateTime.utc(2026, 3, 28, 1, 30), // Fri 27 Mar 23:30 (-2)
          rules: nuuk,
          preferred: preferred,
        );
        final v0 = result.valuesByDay[window[0]];
        expect(v0, DateTime.utc(2026, 3, 29, 0, 59));
        expect(readingOf(v0!, nuuk), wall(2026, 3, 28, 22, 59));
        expect(result.plannedClockTimes[window[0]], wall(2026, 3, 28, 23, 30));
        for (var i = 1; i < 7; i++) {
          expect(result.valuesByDay[window[i]],
              DateTime.utc(2026, 3, 29 + i, 0, 30),
              reason: '${window[i]} is 23:30 (-1)');
        }
        expect(result.overrunNotificationNeeded, isFalse);
      });
    }
  });

  group('T53: no fallback where the date does not change (counter-tests)', () {
    test('America/Santiago, window 6-12 Sep: 6 Sep reads 01:00 on the same '
        'date (plain R), 7 Sep back to 00:30 (-3)', () {
      final loc = tz.getLocation('America/Santiago');
      final window = _window(loc, 2026, 9, 6);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 9, 5, 4, 30), // Sat 5 Sep 00:30 (-4)
        rules: zoneRules(loc),
      );
      expect(result.valuesByDay[window[0]], DateTime.utc(2026, 9, 6, 4, 0));
      expect(result.valuesByDay[window[1]], DateTime.utc(2026, 9, 7, 3, 30));
      expect(result.plannedClockTimes[window[0]], wall(2026, 9, 6, 0, 30));
    });

    test('America/Nuuk autumn, window 24-30 Oct: a repeated 23:30 takes the '
        'second pass and stays on 24 Oct', () {
      final loc = tz.getLocation('America/Nuuk');
      final window = _window(loc, 2026, 10, 24);
      final result = _plan(
        window: window,
        anchor: DateTime.utc(2026, 10, 24, 0, 30), // Fri 23 Oct 23:30 (-1)
        rules: zoneRules(loc),
      );
      expect(result.valuesByDay[window[0]], DateTime.utc(2026, 10, 25, 1, 30));
      expect(result.valuesByDay[window[1]], DateTime.utc(2026, 10, 26, 1, 30));
      expect(result.plannedClockTimes[window[0]], wall(2026, 10, 24, 23, 30));
    });
  });

  test('T14 (counter): an appointment at Mon 30 Mar 12:00 CEST is on 30 Mar '
      'under a fixed +2 and under Berlin\'s rules alike', () {
    final event = _event(DateTime.utc(2026, 3, 30, 10, 0), _berlin);
    for (final (label, rules) in [
      ('fixed +2', fixedOffset(const Duration(hours: 2))),
      ('Berlin rules', _berlinRules),
    ]) {
      for (final (d, expected) in [(29, false), (30, true), (31, false)]) {
        final day = tz.TZDateTime(_berlin, 2026, 3, d);
        expect(eventsForDay(day, allEvents: [event], offsetAt: rules),
            expected ? [event] : isEmpty,
            reason: '$label, 2026-03-$d');
      }
    }
  });

  group('P1/P2: planned clock times carry the intent exactly (T206-R9)', () {
    test('P1 an entry exists iff the day has a value and is not '
        'instant-anchored; P2 the value is exactly R_plan(entry)', () {
      final zones = [
        'Europe/Berlin',
        'America/Nuuk',
        'Australia/Lord_Howe',
        'America/Santiago',
        'Pacific/Chatham',
        'Asia/Tokyo',
      ];
      // Window starts spread over the 2026 transitions of these zones, so
      // many cases contain one; plus the generator's random dates.
      final starts = [
        DateTime.utc(2026, 3, 26),
        DateTime.utc(2026, 3, 28),
        DateTime.utc(2026, 10, 22),
        DateTime.utc(2026, 10, 25),
        DateTime.utc(2026, 4, 3),
        DateTime.utc(2026, 9, 25),
        DateTime.utc(2026, 10, 2),
        DateTime.utc(2026, 9, 5),
        null,
      ];
      final violations = <String>[];
      var n = 0;
      for (final zone in zones) {
        final rules = zoneRules(tz.getLocation(zone));
        for (final start in starts) {
          for (final c in generatePlanCases(25,
              seed: 206 + n++, windowStart: start)) {
            final result = _planCase(c, rules);
            for (final day in c.window) {
              final value = result.valuesByDay[day];
              final entry = result.plannedClockTimes[day];
              final shouldHave =
                  value != null && !result.instantAnchoredDays.contains(day);
              if ((entry != null) != shouldHave) {
                violations.add('P1 $zone $c: $day value $value, anchored '
                    '${result.instantAnchoredDays.contains(day)}, entry $entry');
              } else if (entry != null) {
                if (!entry.isUtc) violations.add('$zone $c: $day entry local');
                final resolved = resolvePlannedClockTime(entry, rules);
                if (resolved.microsecondsSinceEpoch !=
                    value!.microsecondsSinceEpoch) {
                  violations.add('P2 $zone $c: $day value $value, '
                      'R_plan(entry $entry) $resolved');
                }
              }
            }
          }
        }
      }
      expect(violations, isEmpty,
          reason: '${violations.length} violations; first:\n'
              '${violations.take(8).join('\n')}');
    });
  });

  group('T40/T41 (counters): zone rules equal a constant offset wherever the '
      'offset does not change', () {
    test('T40: no-DST zones (Asia/Tokyo, Asia/Kolkata, Asia/Kathmandu, Etc/UTC) - '
        '500 seeded cases each', () {
      final diffs = <String>[];
      for (final (zone, offset) in [
        ('Asia/Tokyo', const Duration(hours: 9)),
        ('Asia/Kolkata', const Duration(hours: 5, minutes: 30)),
        ('Asia/Kathmandu', const Duration(hours: 5, minutes: 45)),
        ('Etc/UTC', Duration.zero),
      ]) {
        final rules = zoneRules(tz.getLocation(zone));
        for (final c in generatePlanCases(500, seed: 40)) {
          diffs.addAll(_differences(_planCase(c, rules),
              _planCase(c, fixedOffset(offset)), c.window, '$zone $c'));
        }
      }
      expect(diffs, isEmpty,
          reason: '${diffs.length} differences; first:\n'
              '${diffs.take(8).join('\n')}');
    });

    test('T41: DST zones away from a transition (Berlin July, Lord Howe and '
        'Chatham January, Santiago July) - 200 seeded cases each', () {
      final diffs = <String>[];
      for (final (zone, start, offset) in [
        ('Europe/Berlin', DateTime.utc(2026, 7, 6), const Duration(hours: 2)),
        ('Australia/Lord_Howe', DateTime.utc(2026, 1, 12),
            const Duration(hours: 11)),
        ('Pacific/Chatham', DateTime.utc(2026, 1, 12),
            const Duration(hours: 13, minutes: 45)),
        ('America/Santiago', DateTime.utc(2026, 7, 13),
            const Duration(hours: -4)),
      ]) {
        final rules = zoneRules(tz.getLocation(zone));
        // Anchors lie within 30 h before the window and events inside it,
        // so every input is weeks away from the zone's transitions.
        for (final c in generatePlanCases(200, seed: 41, windowStart: start)) {
          diffs.addAll(_differences(_planCase(c, rules),
              _planCase(c, fixedOffset(offset)), c.window, '$zone $c'));
        }
      }
      expect(diffs, isEmpty,
          reason: '${diffs.length} differences; first:\n'
              '${diffs.take(8).join('\n')}');
    });
  });
}
