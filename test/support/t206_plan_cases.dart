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

// docs/TODO.md T-206: the seeded random `computeWeekPlan` inputs of the
// requirements' T02 (the Lemma C differential test), reused by T40/T41 (the
// same plan under real zone rules vs. a constant offset) and by the P1/P2
// invariant check. Deterministic: the same seed yields the same cases on
// every machine and in every CI leg.
//
// Window days are UTC-tagged markers - the production frame of the pure
// layer (replan hands it date markers read by their calendar fields). A
// local `_t`-style fixture would exercise the legacy file's local
// `_dateTimeLike` branch instead (requirements T02, G§1.1).
//
// Not a test file itself (no `_test.dart` suffix).

import 'dart:math';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';

const List<int> _leadMinutes = [0, 15, 30, 60, 120];
const List<int> _maxDeltaMinutes = [15, 20, 30, 45, 60, 90];

/// One generated `computeWeekPlan` input.
class PlanCase {
  PlanCase({
    required this.index,
    required this.window,
    required this.anchor,
    required this.events,
    required this.durationToWakeUp,
    required this.durationToGetReady,
    required this.preferredWakeUpTime,
    required this.maxDailyDelta,
    required this.gapDayCounter,
    required this.scheduleOnGapDays,
  });

  final int index;
  final List<DateTime> window;
  final DateTime? anchor;
  final List<Meeting> events;
  final Duration durationToWakeUp;
  final Duration durationToGetReady;
  final TimeOfDay? preferredWakeUpTime;
  final Duration maxDailyDelta;
  final int gapDayCounter;
  final bool scheduleOnGapDays;

  @override
  String toString() => 'case #$index: window ${window.first.toIso8601String()}'
      ', anchor ${anchor?.toIso8601String()}, events '
      '${events.map((e) => '${e.from.toUtc().toIso8601String()}'
          '${e.isAllDay ? ' (all-day)' : ''}').toList()}, wakeUp '
      '${durationToWakeUp.inMinutes}m, getReady '
      '${durationToGetReady.inMinutes}m, P $preferredWakeUpTime, md '
      '${maxDailyDelta.inMinutes}m, gapDayCounter $gapDayCounter, '
      'scheduleOnGapDays $scheduleOnGapDays';
}

/// [count] seeded cases. [windowStart] fixes the window's first day (a
/// UTC-tagged midnight); by default each case starts on a random 2026/27
/// date. Anchors lie within 30 h before the window, events inside it.
List<PlanCase> generatePlanCases(int count,
    {required int seed, DateTime? windowStart}) {
  final rng = Random(seed);
  final cases = <PlanCase>[];
  for (var index = 0; index < count; index++) {
    final start = windowStart ??
        DateTime.utc(2026, 1, 1 + rng.nextInt(2 * 365 - 7));
    final window = List.generate(
        7, (i) => DateTime.utc(start.year, start.month, start.day + i));

    final anchor = rng.nextInt(100) < 20
        ? null
        : start.subtract(Duration(minutes: 1 + rng.nextInt(30 * 60)));

    final events = <Meeting>[];
    for (var e = rng.nextInt(5); e > 0; e--) {
      if (rng.nextInt(100) < 10) {
        final day = window[rng.nextInt(7)];
        events.add(Meeting(
          from: day,
          to: day.add(const Duration(days: 1)),
          isAllDay: true,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        ));
      } else {
        final from = start.add(Duration(minutes: rng.nextInt(7 * 24 * 60)));
        events.add(Meeting(
          from: from,
          to: from.add(const Duration(hours: 1)),
          isAllDay: false,
          startTimeZone: 'Etc/UTC',
          endTimeZone: 'Etc/UTC',
        ));
      }
    }

    cases.add(PlanCase(
      index: index,
      window: window,
      anchor: anchor,
      events: events,
      durationToWakeUp:
          Duration(minutes: _leadMinutes[rng.nextInt(_leadMinutes.length)]),
      durationToGetReady:
          Duration(minutes: _leadMinutes[rng.nextInt(_leadMinutes.length)]),
      preferredWakeUpTime: rng.nextInt(100) < 30
          ? null
          : TimeOfDay(hour: rng.nextInt(24), minute: rng.nextInt(60)),
      maxDailyDelta: Duration(
          minutes: _maxDeltaMinutes[rng.nextInt(_maxDeltaMinutes.length)]),
      gapDayCounter: rng.nextInt(9),
      scheduleOnGapDays: rng.nextBool(),
    ));
  }
  return cases;
}
