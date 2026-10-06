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

// docs/TODO.md T-139, decided by the maintainer on 2026-10-05 (verbatim):
// "Das klingt falsch, es sollte jede Zeit jedes Tages getestet werden und der
// Sprung eigentlich gar nicht auftreten." ("That sounds wrong - every time of
// every day should be tested, and the jump should not occur at all.")
//
// A worked example only ever covers the case someone thought of. This file
// checks the planned week against INVARIANTS over seeded random windows
// (test/support/plan_invariants.dart states them independently of the
// engine's own procedure):
//
// - FR-2, always: no day is planned later than its own hardFloor.
// - FR-6/FR-7 smoothness, whenever a step-bounded curve exists at all: no
//   visible step above maxDailyDelta per day, no overrun notification.
// - FR-7 timing, both directions: no day earlier than necessary and none
//   later than the hold or the FR-4 drift allow (see timingViolations).
//
// Seven families, each with gapDayCounter 0..9 and scheduleOnGapDays on/off
// (so FR-9's valve and T-52.1's mask take part):
//
// - DAY: times of day 03:00-11:00, fixed offsets incl. +5:45, -3:30, +12:45.
// - EVENING: 14:00-23:30 - an evening or late shift, anchor on its own day.
// - EVENING MIX: a morning anchor and morning appointments (03:00-09:00)
//   with evening appointments (17:00-22:30) on later days - the T-208 shape
//   the re-audit of 2026-10-06 found: an evening hardFloor more than 12 hours
//   after a morning value read as "earlier" and pulled a run toward it.
// - ROTA: anchor and appointments at any time of day, anchor on its own day -
//   a rota that changes between night and day shifts (Marie, personas.md).
//   This is where a point more than 12 hours earlier reads as later under
//   FR-1's wrap (the T-139 review's B1, differential case #49).
// - SHIFT: a night shift's anchor - 17:00-23:59 on the date BEFORE its day
//   (T-118b: the alarm for a 00:00 shift rings the evening before) - with
//   appointments at any time of day. Smoothness is not decidable by plain
//   reading arithmetic there and is skipped; FR-2 and FR-7 timing are checked.
//   This is the shape (differential case #22) where the first version of
//   T-139's fix started runs too early.
// - DST: Europe/Berlin and America/Nuuk rules injected, windows across their
//   2026 transitions, times 03:00-11:00 (outside both zones' skipped and
//   repeated hours).
// - DST NIGHT: Europe/Berlin, times 01:00-04:00 and preferred times 02:00-03:00
//   - inside the skipped and repeated hour, where a day's planned clock time
//   differs from the reading its instant shows.
//
// The seed is fixed: a failure prints its family, case number and inputs.

import 'dart:math';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/plan_invariants.dart';
import 'support/zone_rules.dart';

Meeting _meetingAt(DateTime from) => Meeting(
      from: from,
      to: from.add(const Duration(hours: 1)),
      isAllDay: false,
      startTimeZone: 'Etc/UTC',
      endTimeZone: 'Etc/UTC',
    );

const _deltas = [15, 20, 30, 45, 60, 90];
const _fixedOffsets = [
  Duration.zero,
  Duration(hours: 5, minutes: 45),
  Duration(hours: -3, minutes: -30),
  Duration(hours: 12, minutes: 45),
];

enum _Family { day, evening, eveningMix, rota, shift, dst, dstNight }

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('FR-2, smoothness and FR-7 timing hold over 10,500 seeded random windows',
      () {
    final random = Random(20261005);
    final berlin = zoneRules(tz.getLocation('Europe/Berlin'));
    final nuuk = zoneRules(tz.getLocation('America/Nuuk'));
    final violations = <String>[];
    final smoothChecked = <_Family, int>{};
    final failedPerFamily = <_Family, int>{};
    final exactChecked = <_Family, int>{};

    int minuteIn(int fromMinute, int span) =>
        (fromMinute + random.nextInt(span + 1)) % (24 * 60);

    for (var c = 0; c < 10500; c++) {
      final family = _Family.values[c % _Family.values.length];
      final md = _deltas[random.nextInt(_deltas.length)];
      final ZoneOffsetAt rules;
      DateTime windowStart;
      switch (family) {
        case _Family.dstNight:
          rules = berlin;
          windowStart = random.nextBool()
              ? DateTime.utc(2026, 3, 23 + random.nextInt(7))
              : DateTime.utc(2026, 10, 19 + random.nextInt(7));
        case _Family.dst:
          final berlinZone = random.nextBool();
          rules = berlinZone ? berlin : nuuk;
          final spring = random.nextBool();
          windowStart = spring
              ? DateTime.utc(2026, 3, 23 + random.nextInt(7))
              : DateTime.utc(2026, 10, 19 + random.nextInt(7));
        default:
          rules = fixedOffset(_fixedOffsets[random.nextInt(_fixedOffsets.length)]);
          windowStart = DateTime.utc(2026, 1, 10 + random.nextInt(300));
      }
      // A reading on [date] at [minute] as an instant (R, TZ-1).
      // Seconds too: a step over the limit by less than a minute must show.
      DateTime at(DateTime date, int minute) => resolvePlannedClockTime(
          DateTime.utc(date.year, date.month, date.day, 0, minute,
              random.nextInt(60)),
          rules);
      DateTime dayAt(int k) =>
          DateTime.utc(windowStart.year, windowStart.month, windowStart.day + k);

      final (int bandStart, int bandSpan) = switch (family) {
        _Family.day || _Family.dst => (3 * 60, 8 * 60),
        _Family.evening => (14 * 60, 9 * 60 + 30),
        _Family.shift || _Family.rota => (0, 24 * 60 - 1),
        _Family.eveningMix => (3 * 60, 6 * 60),
        _Family.dstNight => (60, 3 * 60),
      };
      final DateTime anchor = switch (family) {
        _Family.shift => at(dayAt(-2), minuteIn(17 * 60, 7 * 60 - 1)),
        _Family.evening => at(dayAt(-1), minuteIn(16 * 60, 6 * 60)),
        _Family.rota => at(dayAt(-1), minuteIn(0, 24 * 60 - 1)),
        _Family.dstNight => at(dayAt(-1), minuteIn(90, 2 * 60)),
        _ => at(dayAt(-1), minuteIn(5 * 60, 5 * 60)),
      };
      final lead = family == _Family.shift
          ? Duration(minutes: [0, 30, 60, 120][random.nextInt(4)])
          : Duration.zero;
      final events = <Meeting>[];
      for (var k = 0; k < 7; k++) {
        if (random.nextDouble() < 0.45) {
          events.add(_meetingAt(
              at(dayAt(k), minuteIn(bandStart, bandSpan)).add(lead)));
        }
        // EVENING MIX: evening appointments too, on days of their own or
        // beside a morning one (the earlier one is the day's hardFloor).
        if (family == _Family.eveningMix && random.nextDouble() < 0.35) {
          events.add(_meetingAt(at(dayAt(k), minuteIn(17 * 60, 5 * 60 + 30))));
        }
      }
      final preferred = random.nextBool()
          ? null
          : (() {
              final m = switch (family) {
                _Family.shift || _Family.rota => minuteIn(0, 24 * 60 - 1),
                // In the skipped/repeated hour of a Berlin DST night.
                _Family.dstNight => minuteIn(2 * 60, 60),
                _Family.evening => minuteIn(bandStart, bandSpan),
                _ => minuteIn(5 * 60, 5 * 60),
              };
              return TimeOfDay(hour: m ~/ 60, minute: m % 60);
            })();
      final gapDayCounter = random.nextInt(10);
      final scheduleOnGapDays = random.nextInt(4) != 0;
      final window = [for (var k = 0; k < 7; k++) dayAt(k)];

      final result = computeWeekPlan(
        window: window,
        lastEffectiveWakeTime: anchor,
        allEvents: events,
        offsetAt: rules,
        durationToWakeUp: lead,
        durationToGetReadyForDay: (_) => Duration.zero,
        preferredWakeUpTime: preferred,
        maxDailyDelta: Duration(minutes: md),
        gapDayCounter: gapDayCounter,
        scheduleOnGapDays: scheduleOnGapDays,
      );
      final inputs = PlanInputs(
        window: window,
        anchor: anchor,
        events: events,
        lead: lead,
        maxDailyDelta: Duration(minutes: md),
        preferred: preferred,
        rules: rules,
      );

      final found = <String>[
        ...hardFloorViolations(result.valuesByDay, inputs),
      ];
      final timing = timingViolations(
          result.valuesByDay, result.plannedClockTimes, inputs);
      found.addAll(timing.violations);
      exactChecked[family] = (exactChecked[family] ?? 0) + timing.exactChecks;
      if (family != _Family.shift && smoothnessApplies(inputs)) {
        smoothChecked[family] = (smoothChecked[family] ?? 0) + 1;
        found.addAll(smoothnessViolations(
            result.valuesByDay, result.plannedClockTimes,
            result.overrunNotificationNeeded, inputs));
      }
      if (found.isNotEmpty) {
        failedPerFamily[family] = (failedPerFamily[family] ?? 0) + 1;
        violations.add('${family.name} case $c (offset ${rules(anchor)}, '
            'anchor $anchor, md $md, P '
            '$preferred, lead $lead, counter $gapDayCounter, gapDays '
            '$scheduleOnGapDays, events ${events.map((e) => e.from).toList()}'
            '): ${found.join('; ')}; plan ${result.valuesByDay.values.toList()}');
      }
    }

    expect(violations, isEmpty,
        reason: '${violations.length} cases violate an invariant '
            '(per family: $failedPerFamily); first ones:\n'
            '${violations.take(5).join('\n')}');
    // The generator must actually exercise the smoothness property.
    for (final f in [
      _Family.day,
      _Family.evening,
      _Family.eveningMix,
      _Family.dst
    ]) {
      expect(smoothChecked[f] ?? 0, greaterThan(500),
          reason: 'smoothness decided too rarely in ${f.name}');
    }
    // ROTA too, at a lower bar by construction: its anchor, appointments and
    // preferred time are drawn from the whole day, and smoothness is decided
    // only where all of them fall within 11 hours without crossing midnight
    // (smoothnessApplies) - about a quarter of ROTA's windows (350 of 1,500
    // at this seed). The rest is the open night-shift date question; there
    // FR-2 and FR-7 timing still decide every window.
    expect(smoothChecked[_Family.rota] ?? 0, greaterThan(250),
        reason: 'smoothness decided too rarely in rota');
    // ... and the exact FR-7 timing check, in every family.
    for (final f in _Family.values) {
      expect(exactChecked[f] ?? 0, greaterThan(1000),
          reason: 'FR-7 timing decided exactly too rarely in ${f.name} '
              '($exactChecked)');
    }
  });
}
