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

// docs/TODO.md T-206, requirements T02 ("Lemma C", Günther's K15): with ONE
// constant offset, the new computation - zone rules injected as a function,
// planning in reading space - must produce exactly what the pure layer did
// before T-206 (the verbatim snapshot in
// test/support/scheduling_v2_legacy_8ac1d9e.dart). Where the offset never
// changes, reading space and instant space are the same space shifted by a
// constant, so any difference is a regression, not a DST fix.
//
// Green by design at every stage (S1, S2, S3): it guards the refactor, it is
// not a red-first regression. Deliberately pure and injected, so it means
// the same in every CI leg.

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/scheduling_v2_legacy_8ac1d9e.dart' as legacy;
import 'support/t206_plan_cases.dart';

const _offsets = [
  Duration.zero,
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 5, minutes: 30),
  Duration(hours: 5, minutes: 45),
  Duration(hours: 9),
  Duration(hours: 12, minutes: 45),
  Duration(hours: 13, minutes: 45),
  Duration(hours: -2, minutes: -30),
  Duration(hours: -3, minutes: -30),
  Duration(hours: -10),
];

void main() {
  test(
      'T02: with a constant offset, computeWeekPlan(offsetAt: fixedOffset(d)) '
      'is bit-identical to the 8ac1d9e pure layer (2,000 seeded cases, 11 '
      'offsets)', () {
    final mismatches = <String>[];
    final cases = generatePlanCases(2000, seed: 206);
    for (final c in cases) {
      final d = _offsets[c.index % _offsets.length];
      final old = legacy.computeWeekPlan(
        window: c.window,
        lastEffectiveWakeTime: c.anchor,
        allEvents: c.events,
        deviceUtcOffset: d,
        durationToWakeUp: c.durationToWakeUp,
        durationToGetReadyForDay: (_) => c.durationToGetReady,
        preferredWakeUpTime: c.preferredWakeUpTime,
        maxDailyDelta: c.maxDailyDelta,
        gapDayCounter: c.gapDayCounter,
        scheduleOnGapDays: c.scheduleOnGapDays,
      );
      final current = computeWeekPlan(
        window: c.window,
        lastEffectiveWakeTime: c.anchor,
        allEvents: c.events,
        offsetAt: fixedOffset(d),
        durationToWakeUp: c.durationToWakeUp,
        durationToGetReadyForDay: (_) => c.durationToGetReady,
        preferredWakeUpTime: c.preferredWakeUpTime,
        maxDailyDelta: c.maxDailyDelta,
        gapDayCounter: c.gapDayCounter,
        scheduleOnGapDays: c.scheduleOnGapDays,
      );

      final label = '$c, offset $d';
      for (final day in c.window) {
        final a = old.valuesByDay[day];
        final b = current.valuesByDay[day];
        if (a?.microsecondsSinceEpoch != b?.microsecondsSinceEpoch) {
          mismatches.add('$label: $day legacy $a, current $b');
        }
      }
      if (old.overrunNotificationNeeded != current.overrunNotificationNeeded) {
        mismatches.add('$label: overrun legacy '
            '${old.overrunNotificationNeeded}, current '
            '${current.overrunNotificationNeeded}');
      }
      if (old.safetyValveTriggered != current.safetyValveTriggered) {
        mismatches.add('$label: safety valve legacy '
            '${old.safetyValveTriggered}, current '
            '${current.safetyValveTriggered}');
      }
      final oldAnchored =
          old.instantAnchoredDays.map((d) => d.microsecondsSinceEpoch).toSet();
      final newAnchored = current.instantAnchoredDays
          .map((d) => d.microsecondsSinceEpoch)
          .toSet();
      if (oldAnchored.length != newAnchored.length ||
          !oldAnchored.containsAll(newAnchored)) {
        mismatches.add('$label: instantAnchoredDays legacy '
            '${old.instantAnchoredDays}, current '
            '${current.instantAnchoredDays}');
      }
    }
    expect(mismatches, isEmpty,
        reason: '${mismatches.length} mismatches; first ones:\n'
            '${mismatches.take(10).join('\n')}');
  });
}
