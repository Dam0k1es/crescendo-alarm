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

// docs/TODO.md T-139: invariants of a planned week, stated independently of
// the engine's own procedure (no groupTarget, no FR-7 bisection), shared by
// test/scheduling_v2_smoothness_property_test.dart and the frozen T-139
// allowlist of test/t206_lemma_c_differential_test.dart.
//
// - FR-2: no day is planned later than its own hardFloor (always).
// - FR-6/FR-7 smoothness: whenever a step-bounded curve exists at all, no
//   visible step exceeds maxDailyDelta per day and no overrun is reported.
//   Decided only where readings form a plain line - see [smoothnessApplies].
// - FR-7 timing, both directions ("as late as necessary", and never later
//   than FR-4 allows), restated from the spec rather than from the engine:
//   FR-1 decides which later hardFloors read as EARLIER than yesterday's
//   value (only those can be FR-5 targets); FR-4 gives the intended value
//   (hold, or one step of at most maxDailyDelta toward the preferred time);
//   if the intended value keeps every such target reachable - falling by
//   maxDailyDelta a day, on the dates the days fall on - and does not
//   overshoot one by more than the days left can bring back, the day IS the
//   intended value, capped by its own hardFloor. Otherwise it is at least
//   never later than both the hold and the intended value.
//
// Values are compared at full (microsecond) resolution. Not a test file
// itself (no `_test.dart` suffix).

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

const _dayMicros = 24 * 60 * 60 * 1000000;
const _halfDayMicros = _dayMicros ~/ 2;

/// The inputs of one `computeWeekPlan` call, as far as the invariants need
/// them. [lead] is durationToWakeUp + durationToGetReady (one value for the
/// whole window).
class PlanInputs {
  PlanInputs({
    required this.window,
    required this.anchor,
    required this.events,
    required this.lead,
    required this.maxDailyDelta,
    required this.preferred,
    required this.rules,
  });

  final List<DateTime> window;
  final DateTime? anchor;
  final List<Meeting> events;
  final Duration lead;
  final Duration maxDailyDelta;
  final TimeOfDay? preferred;
  final ZoneOffsetAt rules;
}

DateTime readingAt(DateTime instant, ZoneOffsetAt rules) =>
    instant.toUtc().add(rules(instant));

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _timeOfDay(DateTime reading) =>
    ((reading.hour * 60 + reading.minute) * 60 + reading.second) * 1000000 +
    reading.millisecond * 1000 +
    reading.microsecond;

/// The time-of-day difference [from] -> [to], wrapped into (-12h, +12h].
int wrapDeltaMicros(DateTime from, DateTime to) {
  var d = _timeOfDay(to) - _timeOfDay(from);
  if (d > _halfDayMicros) d -= _dayMicros;
  if (d <= -_halfDayMicros) d += _dayMicros;
  return d;
}

DateTime _readingDaysLater(DateTime r, int days) => DateTime.utc(r.year,
    r.month, r.day + days, r.hour, r.minute, r.second, r.millisecond,
    r.microsecond);

/// window index -> hardFloor instant: the earliest non-all-day event on the
/// device-local date of each window day, minus [PlanInputs.lead].
Map<int, DateTime> floorsOf(PlanInputs p) {
  final floors = <int, DateTime>{};
  for (final e in p.events) {
    if (e.isAllDay) continue;
    final reading = readingAt(e.from, p.rules);
    final k = p.window.indexWhere((d) => _sameDate(d, reading));
    if (k == -1) continue;
    final floor = e.from.toUtc().subtract(p.lead);
    if (floors[k] == null || floor.isBefore(floors[k]!)) floors[k] = floor;
  }
  return floors;
}

List<String> hardFloorViolations(
    Map<DateTime, DateTime?> values, PlanInputs p) {
  final out = <String>[];
  floorsOf(p).forEach((k, floor) {
    final v = values[p.window[k]];
    if (v != null && v.isAfter(floor)) {
      out.add('FR-2: day $k planned $v, after its hardFloor $floor');
    }
  });
  return out;
}

/// Whether the smoothness invariant can be decided by plain reading
/// arithmetic: an anchor whose reading lies on its own day (the day before
/// the window), every hardFloor's reading on its own day, and the anchor,
/// every hardFloor and the preferred time within an 11-hour span of times of
/// day that does not cross midnight - so no value can come near FR-1's
/// 12-hour wrap and every step reads unambiguously. (Across midnight a
/// 02:00 hardFloor and a 20:00 value on the same date are 18 hours apart,
/// while FR-1 reads them as 6 hours "later" - that shape is outside what
/// the planning's day convention decides today; see the T-139 review.)
bool smoothnessApplies(PlanInputs p) {
  final anchor = p.anchor;
  if (anchor == null) return false;
  final a = readingAt(anchor, p.rules);
  final dayBefore = DateTime.utc(
      p.window.first.year, p.window.first.month, p.window.first.day - 1);
  if (!_sameDate(a, dayBefore)) return false;
  final offsets = <int>[0];
  for (final entry in floorsOf(p).entries) {
    final r = readingAt(entry.value, p.rules);
    if (!_sameDate(r, p.window[entry.key])) return false;
    offsets.add(_timeOfDay(r) - _timeOfDay(a));
  }
  if (p.preferred case final pref?) {
    offsets.add((pref.hour * 60 + pref.minute) * 60 * 1000000 - _timeOfDay(a));
  }
  final span = offsets.reduce((x, y) => x > y ? x : y) -
      offsets.reduce((x, y) => x < y ? x : y);
  return span < 11 * 60 * 60 * 1000000;
}

/// FR-6/FR-7: only meaningful where [smoothnessApplies]. A step-bounded curve
/// exists exactly when every hardFloor h_k (window index k, k+1 days after
/// the anchor) satisfies A - h_k <= maxDailyDelta * (k+1): falling by
/// maxDailyDelta every day is the earliest such a curve can be, and earlier
/// is always allowed (FR-2). If it exists, every visible step - measured on
/// the planned clock time where the plan records one - across
/// days without a value, the whole shift since the last value - stays
/// within maxDailyDelta per day, and no overrun is reported.
List<String> smoothnessViolations(Map<DateTime, DateTime?> values,
    Map<DateTime, DateTime> plannedClockTimes, bool overrunReported,
    PlanInputs p) {
  final a = readingAt(p.anchor!, p.rules);
  final md = p.maxDailyDelta.inMicroseconds;
  final exists = floorsOf(p).entries.every((e) =>
      -wrapDeltaMicros(a, readingAt(e.value, p.rules)) <= md * (e.key + 1));
  if (!exists) return const [];
  final out = <String>[];
  var lastIndex = -1;
  var lastReading = a;
  for (var k = 0; k < p.window.length; k++) {
    final v = values[p.window[k]];
    if (v == null) continue;
    // A wall-clock day is measured by the reading it was planned as (a
    // skipped 02:30 rings at 03:00 but is no 30-minute step - FR-4, T-206).
    final r = plannedClockTimes[p.window[k]] ?? readingAt(v, p.rules);
    final step = wrapDeltaMicros(lastReading, r).abs();
    if (step > md * (k - lastIndex)) {
      out.add('smoothness: step into day $k is ${step / 60e6} min over '
          '${k - lastIndex} day(s), allowed ${md / 60e6} per day');
    }
    lastIndex = k;
    lastReading = r;
  }
  if (overrunReported) {
    out.add('smoothness: a smooth curve exists, yet an overrun was reported');
  }
  return out;
}

/// FR-7 timing (see the file comment). [plannedClockTimes] is the plan's
/// own record of which reading each wall-clock day was planned as - the
/// next day holds THAT reading (FR-3/FR-4), which differs from the reading
/// its instant shows for a reading in a skipped hour. Checked for every day
/// whose value and whose predecessor's value (the anchor for the first day)
/// exist; with no anchor (FR-10's cold start) only after the first hardFloor
/// day. Returns the violations and how many days the exact check decided.
({List<String> violations, int exactChecks}) timingViolations(
    Map<DateTime, DateTime?> values,
    Map<DateTime, DateTime> plannedClockTimes,
    PlanInputs p) {
  final floors = floorsOf(p);
  final md = p.maxDailyDelta;
  final mdMicros = md.inMicroseconds;
  final out = <String>[];
  var exactChecks = 0;
  final firstFloor = floors.keys.isEmpty
      ? p.window.length
      : floors.keys.reduce((x, y) => x < y ? x : y);
  DateTime resolve(DateTime reading) =>
      resolvePlannedClockTime(reading, p.rules);

  for (var i = 0; i < p.window.length; i++) {
    if (p.anchor == null && i <= firstFloor) continue;
    final v = values[p.window[i]];
    final prev = i == 0 ? p.anchor : values[p.window[i - 1]];
    if (v == null || prev == null) continue;
    final prevReading = (i == 0 ? null : plannedClockTimes[p.window[i - 1]]) ??
        readingAt(prev, p.rules);

    // FR-4's intended reading for today.
    final hold = _readingDaysLater(prevReading, 1);
    var intended = hold;
    if (p.preferred case final pref?) {
      final target = DateTime.utc(
          hold.year, hold.month, hold.day, pref.hour, pref.minute);
      final distance = wrapDeltaMicros(prevReading, target);
      final step = distance.abs() < mdMicros ? distance.abs() : mdMicros;
      intended =
          hold.add(Duration(microseconds: distance.isNegative ? -step : step));
    }

    // FR-1/FR-5: the later hardFloors that read as earlier than yesterday.
    final targets = [
      for (final e in floors.entries)
        if (e.key > i &&
            wrapDeltaMicros(prevReading, readingAt(e.value, p.rules)) < 0)
          e,
    ];
    bool keepsTargets(DateTime reading) => targets.every((e) {
          final days = e.key - i;
          return !resolve(_readingDaysLater(reading, days)
                  .subtract(md * days))
              .isAfter(e.value);
        });
    bool overshoots(DateTime reading) => targets.any((e) =>
        wrapDeltaMicros(reading, readingAt(e.value, p.rules)) >
        mdMicros * (e.key - i));
    // FR-7: holding decides whether a run starts at all.
    final holdKeeps = keepsTargets(hold) && !overshoots(hold);

    final own = floors[i];
    final holdInstant = resolve(hold);
    final intendedInstant = resolve(intended);
    var upper =
        intendedInstant.isAfter(holdInstant) ? intendedInstant : holdInstant;
    if (own != null && own.isBefore(upper)) upper = own;
    if (v.isAfter(upper)) {
      out.add('timing: day $i planned $v, later than both the hold and the '
          'FR-4 drift allow (upper bound $upper)');
    }
    if (holdKeeps) {
      // No run starts: never earlier than hold, drift and own cap allow.
      var lower = intendedInstant.isBefore(holdInstant)
          ? intendedInstant
          : holdInstant;
      if (own != null && own.isBefore(lower)) lower = own;
      if (v.isBefore(lower)) {
        out.add('timing: day $i planned $v, earlier than necessary - holding '
            'keeps every target reachable (lower bound $lower)');
      }
    }
    // ... and the other way round: if holding loses a target, a run is due.
    // Where a step-bounded curve still exists - falling by maxDailyDelta from
    // today on reaches every target - today's value itself must keep every
    // target reachable (an engine that never starts a run fails here).
    //
    // Not decided where a later hardFloor that FR-1 reads as LATER would still
    // be violated by holding on its date - an early-morning appointment after
    // an evening value, 18 hours earlier by the date but "6 hours later" by
    // FR-1's wrap. FR-5's violation check then shrinks the target onto that
    // point, which is only a cap: the open night-shift date question (T-139
    // review), not something this invariant can settle.
    final hiddenCap = floors.entries.any((e) =>
        e.key > i &&
        !targets.any((t) => t.key == e.key) &&
        resolve(_readingDaysLater(hold, e.key - i)).isAfter(e.value));
    if (!holdKeeps && !hiddenCap && keepsTargets(hold.subtract(md))) {
      final r = plannedClockTimes[p.window[i]] ?? readingAt(v, p.rules);
      if (!keepsTargets(r)) {
        out.add('timing: day $i planned $v; holding loses a target that is '
            'still reachable, and this value does not keep it reachable');
      }
    }
    if (holdKeeps && keepsTargets(intended) && !overshoots(intended)) {
      exactChecks++;
      final expected =
          own != null && own.isBefore(intendedInstant) ? own : intendedInstant;
      if (v != expected) {
        out.add('timing: day $i planned $v; the FR-4 value keeps every '
            'target reachable, so it should be $expected');
      }
    }
  }
  return (violations: out, exactChecks: exactChecks);
}
