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
//
// The T-139 allowlist (docs/TODO.md T-139, maintainer decision 2026-10-05).
// T-139 changed FR-5 step 2 and FR-7 ON PURPOSE, after 8ac1d9e: a reached
// point no longer ends the lookahead, FR-7's feasibility checks every point
// FR-5 can target in groupTarget's frame, and times of day are compared with
// their milliseconds. The oracle stays byte-verbatim, so for the cases that
// change it cannot decide anything any more. Those cases are frozen in
// [_t139Divergent], computed once against this engine: 265 of the 2,000.
// By where the anchor's reading lies: 129 on its own day (the day before the
// window), 90 on the date before that (a night shift's alarm the evening
// before, T-118b), 24 on the window's first date (a generator artefact: an
// anchor shifted forward by the offset - the opposite shape), and 22 cold
// starts. Differential case #49 (the review's B1, a night-to-day change) is
// bit-identical again and not in the set.
// For them the oracle is replaced by independent invariants
// (test/support/plan_invariants.dart): FR-2 and FR-7's timing in both
// directions for all 265, smoothness only where readings decide it (an
// anchor on its own day and no midnight in between - none of the 90 + 24).
// Every other case must stay bit-identical. The test fails if the set of
// divergent cases changes in either direction: a new divergence is
// unexplained, a vanished one means the allowlist no longer describes the
// engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/scheduling/scheduling_v2.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/plan_invariants.dart';
import 'support/scheduling_v2_legacy_8ac1d9e.dart' as legacy;
import 'support/t206_plan_cases.dart';

/// docs/TODO.md T-139 (maintainer decision 2026-10-05, FR-5 step 2 and
/// FR-7 changed on purpose): the cases of the 2,000 below whose plan
/// legitimately differs from the 8ac1d9e oracle. Frozen - see the header.
const Set<int> _t139Divergent = {
  7, 21, 22, 30, 33, 37, 41, 44, 45, 74, 94, 100, 101, 114, 120, 121, 124,
  126, 135, 138, 145, 162, 166, 171, 182, 202, 255, 263, 266, 272, 273, 276,
  279, 282, 284, 288, 296, 299, 317, 325, 328, 340, 347, 351, 352, 358, 366,
  370, 373, 383, 393, 396, 407, 428, 436, 441, 446, 449, 456, 460, 475, 487,
  494, 503, 505, 506, 511, 525, 529, 534, 538, 544, 548, 549, 554, 561, 565,
  573, 591, 595, 614, 621, 635, 646, 650, 654, 656, 658, 670, 671, 673, 679,
  692, 705, 710, 711, 714, 717, 727, 729, 736, 752, 763, 779, 785, 793, 813,
  816, 824, 839, 846, 853, 855, 857, 879, 882, 887, 897, 910, 924, 937, 938,
  943, 945, 959, 965, 975, 976, 979, 981, 987, 996, 1004, 1005, 1013, 1019,
  1021, 1032, 1033, 1035, 1045, 1055, 1061, 1066, 1070, 1082, 1097, 1105,
  1112, 1121, 1122, 1136, 1138, 1146, 1147, 1150, 1153, 1155, 1173, 1175,
  1181, 1184, 1186, 1187, 1200, 1201, 1211, 1222, 1223, 1232, 1241, 1261,
  1264, 1265, 1273, 1285, 1289, 1298, 1313, 1318, 1319, 1320, 1333, 1339,
  1350, 1351, 1374, 1378, 1395, 1419, 1424, 1431, 1432, 1458, 1459, 1461,
  1472, 1474, 1492, 1495, 1506, 1510, 1534, 1540, 1569, 1570, 1583, 1592,
  1594, 1611, 1615, 1621, 1622, 1627, 1630, 1632, 1645, 1658, 1659, 1666,
  1673, 1680, 1681, 1682, 1683, 1691, 1704, 1706, 1718, 1725, 1736, 1737,
  1738, 1740, 1743, 1761, 1770, 1780, 1782, 1793, 1797, 1803, 1804, 1805,
  1817, 1820, 1823, 1825, 1830, 1837, 1868, 1884, 1900, 1902, 1911, 1912,
  1913, 1934, 1944, 1950, 1960, 1961, 1975, 1990, 1991,
};

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
    final divergent = <int>{};
    final invariantFailures = <String>[];
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
      final caseMismatches = <String>[];
      for (final day in c.window) {
        final a = old.valuesByDay[day];
        final b = current.valuesByDay[day];
        if (a?.microsecondsSinceEpoch != b?.microsecondsSinceEpoch) {
          caseMismatches.add('$label: $day legacy $a, current $b');
        }
      }
      if (old.overrunNotificationNeeded != current.overrunNotificationNeeded) {
        caseMismatches.add('$label: overrun legacy '
            '${old.overrunNotificationNeeded}, current '
            '${current.overrunNotificationNeeded}');
      }
      if (old.safetyValveTriggered != current.safetyValveTriggered) {
        caseMismatches.add('$label: safety valve legacy '
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
        caseMismatches.add('$label: instantAnchoredDays legacy '
            '${old.instantAnchoredDays}, current '
            '${current.instantAnchoredDays}');
      }
      if (caseMismatches.isEmpty) continue;
      divergent.add(c.index);
      if (!_t139Divergent.contains(c.index)) {
        mismatches.addAll(caseMismatches);
        continue;
      }
      // An allowlisted case: the oracle no longer decides it, the
      // independent invariants do.
      final inputs = PlanInputs(
        window: c.window,
        anchor: c.anchor,
        events: c.events,
        lead: c.durationToWakeUp + c.durationToGetReady,
        maxDailyDelta: c.maxDailyDelta,
        preferred: c.preferredWakeUpTime,
        rules: fixedOffset(d),
      );
      invariantFailures.addAll([
        ...hardFloorViolations(current.valuesByDay, inputs),
        ...timingViolations(
                current.valuesByDay, current.plannedClockTimes, inputs)
            .violations,
        if (smoothnessApplies(inputs))
          ...smoothnessViolations(current.valuesByDay,
              current.plannedClockTimes, current.overrunNotificationNeeded,
              inputs),
      ].map((v) => '$label: $v'));
    }
    expect(mismatches, isEmpty,
        reason: '${mismatches.length} mismatches outside the T-139 '
            'allowlist; first ones:\n${mismatches.take(10).join('\n')}');
    expect(invariantFailures, isEmpty,
        reason: 'allowlisted cases breaking an invariant:\n'
            '${invariantFailures.take(10).join('\n')}');
    // Frozen: the allowlist may neither grow (caught above) nor keep a case
    // that is bit-identical again.
    expect(divergent, _t139Divergent,
        reason: 'divergent cases: ${(divergent.toList()..sort())}');
  });
}
