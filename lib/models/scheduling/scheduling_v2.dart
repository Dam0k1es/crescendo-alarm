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

// Scheduling logic v2 (docs/scheduling-v2-spec.md). Pure functions only - no
// AppState, no BuildContext, no plugin access, so every function here is
// directly unit-testable without mocks (see test/scheduling_v2_test.dart).
//
// Convention (spec, Phase 0): "Instant" is represented as a plain [DateTime];
// "preferredWakeUpTime" as a [TimeOfDay]; day windows as plain integer day-offsets.
//
// docs/TODO.md T-206 (FR-1, maintainer decision A): two kinds of time value.
// Every value going in or out of this file's public functions is an INSTANT
// (UTC-tagged); the size and sign of a daily shift are decided on local
// clock READINGS - a date plus a time of day as the device's clock shows
// it, carried as a UTC-tagged `DateTime` whose digits are that reading.
// Reading space has no transitions, so "the same time, one day later" is
// exact there. The two meet in exactly two places:
//
// - an instant's reading is `_reading(t)` = L(t), with the zone's rules AT
//   that instant;
// - a reading becomes an instant only through `resolvePlannedClockTime`
//   (R_plan, TZ-1/TZ-2a), with the rules for the day it applies to.
//
// A reading is never compared with an instant: FR-2's upper bound is
// applied after R_plan, on instants. The zone's rules arrive as a function
// value ([ZoneOffsetAt]), never from ambient state.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart' show Meeting;
import 'package:crescendo_alarm/utils/wall_clock.dart'
    show ZoneOffsetAt, resolvePlannedClockTime;

/// One real `hardFloor` point in the visible window (FR-2/FR-5), [dayOffset]
/// relative to whichever anchor day is currently under consideration.
class HardFloorPoint {
  const HardFloorPoint({required this.dayOffset, required this.value});

  final int dayOffset;
  final DateTime value;

  @override
  bool operator ==(Object other) =>
      other is HardFloorPoint &&
      other.dayOffset == dayOffset &&
      other.value == value;

  @override
  int get hashCode => Object.hash(dayOffset, value);

  @override
  String toString() => 'HardFloorPoint(dayOffset: $dayOffset, value: $value)';
}

/// The result of distributing a run from an anchor to a target across [n]
/// days (FR-6). Keys of [valuesByDayOffset] run 1..n; key n's value always
/// equals the target exactly.
class DistributionResult {
  const DistributionResult({
    required this.valuesByDayOffset,
    required this.overrunNotificationNeeded,
  });

  final Map<int, DateTime> valuesByDayOffset;
  final bool overrunNotificationNeeded;
}

/// The wall-clock-of-day (time only, no date) microseconds-since-midnight
/// reading of [t].
///
/// Milliseconds included (T-139 review): `DateTime.microsecond` is only the
/// 0-999 microsecond field, so without them a value from FR-7's bisection
/// was misread by up to 999 ms.
int _timeOfDayMicros(DateTime t) =>
    ((t.hour * 60 + t.minute) * 60 + t.second) * 1000000 +
    t.millisecond * 1000 +
    t.microsecond;

/// FR-1's single-step wraparound resolution, applied to a **wall-clock-only**
/// delta: [target]'s own real calendar date is irrelevant here - only its
/// time-of-day matters, compared against [anchor]'s time-of-day, resolving
/// the ambiguity by picking whichever of "later today" / "earlier today"
/// wraps across at most one midnight (i.e. keeping |Δ| <= 12h). This is what
/// lets `distribute()` interpolate a smooth, small wake-time shift per day
/// even when [anchor] and [target] carry real calendar dates that are many
/// days apart (a future `hardFloor` point's own date is only used to place it
/// correctly within a window - never to compute how *far*, in wall-clock
/// terms, the wake time itself needs to move).
///
/// docs/TODO.md T-206: both arguments are local READINGS (FR-1), never
/// instants - the digits compared are the ones the device's clock shows.
Duration _wallClockDelta(DateTime anchor, DateTime target) {
  var deltaMicros = _timeOfDayMicros(target) - _timeOfDayMicros(anchor);
  const dayMicros = 24 * 60 * 60 * 1000000;
  const halfDayMicros = dayMicros ~/ 2;
  if (deltaMicros > halfDayMicros) deltaMicros -= dayMicros;
  if (deltaMicros <= -halfDayMicros) deltaMicros += dayMicros;
  return Duration(microseconds: deltaMicros);
}

/// FR-1's `ΔT` between two local readings [from] and [to] (docs/TODO.md
/// T-206): the difference of their times of day, wrapped into (-12h, +12h].
/// Public for the diagnostics' step measure (`replan.dart`), which must use
/// the same arithmetic as the planning it describes.
Duration readingDelta(DateTime from, DateTime to) => _wallClockDelta(from, to);

/// L(t) (FR-1): the local reading the device's clock shows at [instant],
/// with the zone's rules AT that instant - UTC-tagged, digits = the reading.
DateTime _reading(DateTime instant, ZoneOffsetAt offsetAt) =>
    instant.toUtc().add(offsetAt(instant));

/// The same time of day as the reading [reading], [days] calendar days
/// later - exact in reading space, which has no transitions (docs/TODO.md
/// T-206: this replaces `_dateTimeLike`, whose instant-space construction was
/// right only while the offset stayed constant).
DateTime _readingDaysLater(DateTime reading, int days) => DateTime.utc(
      reading.year,
      reading.month,
      reading.day + days,
      reading.hour,
      reading.minute,
      reading.second,
      reading.millisecond,
      reading.microsecond,
    );

/// [distribute] in reading space: the curve's values are READINGS.
DistributionResult _distributeReadings({
  required DateTime anchor,
  required DateTime target,
  required int n,
  required Duration maxDailyDelta,
}) {
  assert(n >= 1, 'a run must span at least one day');

  final deltaT = _wallClockDelta(anchor, target);
  final deltaMicros = deltaT.inMicroseconds.abs();
  final sign = deltaT.isNegative ? -1 : 1;

  final values = <int, DateTime>{};
  for (var i = 1; i <= n; i++) {
    // Computed from the original deltaMicros each time (not by repeatedly
    // adding a pre-rounded per-day step), so day n always lands exactly on
    // target's wall-clock reading regardless of whether deltaMicros divides
    // evenly by n.
    final stepMicros = (deltaMicros * i) ~/ n;
    values[i] = _readingDaysLater(anchor, i)
        .add(Duration(microseconds: sign * stepMicros));
  }

  final overrunNotificationNeeded =
      deltaMicros > maxDailyDelta.inMicroseconds * n;

  return DistributionResult(
    valuesByDayOffset: values,
    overrunNotificationNeeded: overrunNotificationNeeded,
  );
}

/// FR-6: distributes the wall-clock-time difference between [anchor] and
/// [target] evenly across [n] days, placing day i on its own real calendar
/// date (`anchor`'s date + i) - never on the real, possibly many-days-distant
/// date [target] itself might carry (see [_wallClockDelta]). If the
/// resulting per-day step exceeds [maxDailyDelta], the excess is still spread
/// evenly across all n days (never dumped onto a single day) - except that
/// for n=1 a single-day jump is unavoidable and not itself a spec violation.
/// Either way, [overrunNotificationNeeded] is set whenever maxDailyDelta is
/// exceeded.
///
/// docs/TODO.md T-206: [anchor], [target] and the result are instants; the
/// curve itself is built on their local readings under [offsetAt] (FR-1: the
/// size and sign of a shift are decided on readings), and each day's value is
/// resolved by R_plan with that day's own rules - so a daylight-saving change
/// inside the run is not a shift.
DistributionResult distribute({
  required DateTime anchor,
  required DateTime target,
  required int n,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) {
  final curve = _distributeReadings(
    anchor: _reading(anchor, offsetAt),
    target: _reading(target, offsetAt),
    n: n,
    maxDailyDelta: maxDailyDelta,
  );
  return DistributionResult(
    valuesByDayOffset: curve.valuesByDayOffset
        .map((i, w) => MapEntry(i, resolvePlannedClockTime(w, offsetAt))),
    overrunNotificationNeeded: curve.overrunNotificationNeeded,
  );
}

/// FR-4 in reading space: the day after [vReading]'s own date, holding its
/// time of day or drifting it toward [preferredWakeUpTime] by at most
/// [maxDailyDelta] - a READING.
DateTime _gapDayDriftReading({
  required DateTime vReading,
  required TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
}) {
  final todayReading = _readingDaysLater(vReading, 1);
  if (preferredWakeUpTime == null) return todayReading;

  final target = DateTime.utc(todayReading.year, todayReading.month,
      todayReading.day, preferredWakeUpTime.hour, preferredWakeUpTime.minute);
  final distance = _wallClockDelta(vReading, target);
  if (distance == Duration.zero) return todayReading;

  final step = distance.abs() < maxDailyDelta ? distance.abs() : maxDailyDelta;
  return todayReading.add(distance.isNegative ? -step : step);
}

/// FR-4, isolated from FR-7's cap: computes **today**'s (the day after `v`'s own
/// **device-local** date - the day actually being planned) wake time by
/// drifting `v` towards [preferredWakeUpTime] by at most [maxDailyDelta], stopping
/// exactly at [preferredWakeUpTime] rather than overshooting. Holds at `v`'s clock
/// reading (on today's date) if [preferredWakeUpTime] is null or already reached.
///
/// [v] and the return value are absolute instants (FR-1); [preferredWakeUpTime] is a
/// bare device-local `TimeOfDay` with no date or zone of its own (FR-3). That
/// mismatch is exactly why the zone's rules [offsetAt] are needed here
/// (`docs/TODO.md` T-61): combining preferredWakeUpTime's digits with `v`'s
/// *raw* fields would compare a device-local wall clock against a UTC one and
/// drift by the offset on any device outside UTC+0. Everything below
/// therefore happens in the local reading - `v`'s under the rules at `v`,
/// T-206 - and only the result is resolved back to an instant, by R_plan
/// with the rules of the day it applies to.
DateTime applyGapDayDrift({
  required DateTime v,
  required TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) =>
    resolvePlannedClockTime(
      _gapDayDriftReading(
        vReading: _reading(v, offsetAt),
        preferredWakeUpTime: preferredWakeUpTime,
        maxDailyDelta: maxDailyDelta,
      ),
      offsetAt,
    );

/// FR-2: which of [allEvents] fall on [day] - the calendar date the device's
/// clock shows at each event's own instant, under the device zone's rules
/// [offsetAt] **at that instant** (docs/TODO.md T-119/T-206: not the offset in
/// effect when planning, which puts an appointment shortly after midnight
/// after a daylight-saving change onto the previous day) - and **never** by
/// an event's own zone (that's already baked into `.from` as an absolute
/// instant by existing, unchanged conversion code, see FR-2 "The
/// appointment's own time zone"). The rules are an explicit parameter rather
/// than `DateTime.toLocal()` so this stays deterministic regardless of the
/// host machine's own configured timezone (see FR-2 "Testability"). [day] is
/// read by its calendar fields only.
List<Meeting> eventsForDay(
  DateTime day, {
  required List<Meeting> allEvents,
  required ZoneOffsetAt offsetAt,
}) {
  return allEvents.where((event) {
    final local = _reading(event.from, offsetAt);
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }).toList();
}

/// FR-2: the upper bound ("not later than") for [day], or null if [day] is a
/// gap day (only all-day events, or none at all).
DateTime? hardFloor({
  required DateTime day,
  required List<Meeting> allEvents,
  required ZoneOffsetAt offsetAt,
  required Duration durationToWakeUp,
  required Duration durationToGetReady,
}) {
  final dayEvents = eventsForDay(
    day,
    allEvents: allEvents,
    offsetAt: offsetAt,
  );
  final nonAllDay = dayEvents.where((event) => !event.isAllDay);
  if (nonAllDay.isEmpty) return null;

  final earliest = nonAllDay.reduce((a, b) => a.from.isBefore(b.from) ? a : b);
  // docs/TODO.md T-61: normalise the frame. `Meeting.from` is what
  // `device_calendar` produced - a `TZDateTime` in the **event's own** zone,
  // whose `.hour`/`.minute` are that zone's digits. Every other value in this
  // layer is UTC-tagged, and `_wallClockDelta` compares digit fields, so
  // handing the event's own frame onward made ΔT wrong by the device offset on
  // any device outside UTC+0 (empirically: a 09:00 Berlin event produced a
  // wake time two hours late). `.toUtc()` keeps the exact same real moment
  // (FR-1/FR-16: the appointment does not move) and puts it in the one frame
  // the whole layer shares. (Since T-206, ΔT is taken on `_reading`s, which
  // normalise their input themselves; the `.toUtc()` keeps this result in
  // the layer's convention.)
  return earliest.from
      .toUtc()
      .subtract(durationToWakeUp)
      .subtract(durationToGetReady);
}

/// FR-1/FR-2/FR-5 (re-audit 2026-10-06, the T-208 shape): whether [point]
/// reads as EARLIER than [anchorReading] under FR-1's 12-hour wrap only
/// because it lies more than 12 hours LATER on its own date - an evening
/// appointment after a morning value. FR-2 bounds a day by its own
/// hardFloor, and a morning value on that date already lies before it, so
/// such a point is only its own day's cap: never a run target (FR-5) and
/// never a reason to start a run (FR-7). Decided on the point's own date:
/// the anchor's time of day carried onto that date ([HardFloorPoint.dayOffset]
/// days on) against the point's reading. Only where both fall on the same
/// date - a value whose reading has crossed midnight onto another date
/// (T-225, a night shift's date) keeps FR-1's wrapped reading, unchanged.
bool _capOnlyOnItsDate(
    DateTime anchorReading, HardFloorPoint point, ZoneOffsetAt offsetAt) {
  final pointReading = _reading(point.value, offsetAt);
  if (!_wallClockDelta(anchorReading, pointReading).isNegative) return false;
  final onItsDate = _readingDaysLater(anchorReading, point.dayOffset);
  final sameDate = onItsDate.year == pointReading.year &&
      onItsDate.month == pointReading.month &&
      onItsDate.day == pointReading.day;
  return sameDate && !pointReading.isBefore(onItsDate);
}

/// [groupTarget] with the anchor given as a READING (docs/TODO.md T-206):
/// the planning loop's anchor may be a stored planned clock time, which its
/// instant cannot recover (a skipped reading).
HardFloorPoint _groupTargetFromReading({
  required DateTime anchorReading,
  required List<HardFloorPoint> points,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) {
  assert(
      points.isNotEmpty, 'groupTarget needs at least one real hardFloor point');

  // FR-5 step 2 (docs/TODO.md T-139, maintainer decision 2026-10-05): a
  // ΔT=0 point - one the anchor has already reached - is NOT a cut-off for
  // the candidates. Until T-139 the list was cut at the first such point
  // (T-104), and that hid every later, earlier point from FR-7's lookahead:
  // anchor Sun 07:00, Fri 06:00, Sat 04:00, maxDailyDelta 30 held Tuesday's
  // 06:00 on Wednesday and Thursday (from Wednesday on - its anchor is
  // Tuesday's 06:00 - Friday had ΔT=0) and then needed two 60-minute
  // steps for Saturday - the spec's own FR-7 example, which promises 30-minute
  // steps throughout.
  //
  // What step 2 is still for needs no rule of its own: grouping a ΔT=0 point
  // with a following LATER point would raise the curve above the ΔT=0 point's
  // own hardFloor (it IS the anchor's reading), and step 1's violation check
  // below already rejects exactly that. A following EARLIER point lowers the
  // curve below it, which FR-2 always allows - that is the case that must be
  // grouped through.
  for (var m = points.length; m >= 1; m--) {
    final target = points[m - 1];
    // FR-5's precondition, on the point's own date: an evening appointment
    // after a morning value is no target, however FR-1's wrap reads it. It
    // stays in the violation check below as an intermediate point.
    if (_capOnlyOnItsDate(anchorReading, target, offsetAt)) continue;
    final curve = _distributeReadings(
      anchor: anchorReading,
      target: _reading(target.value, offsetAt),
      n: target.dayOffset,
      maxDailyDelta: maxDailyDelta,
    );

    var violated = false;
    for (var j = 0; j < m - 1; j++) {
      final intermediate = points[j];
      // FR-1/FR-5 (T-206): an upper bound is compared on INSTANTS - the
      // curve's reading resolved first, then against the hardFloor instant.
      final interpolated = resolvePlannedClockTime(
          curve.valuesByDayOffset[intermediate.dayOffset]!, offsetAt);
      if (interpolated.isAfter(intermediate.value)) {
        violated = true;
        break;
      }
    }
    if (!violated) return target;
  }

  // Reached only when every point is a same-date cap (m=1 has no
  // intermediate points to violate): no target at all, and the caller's
  // FR-5 precondition treats this one as such.
  return points.first;
}

/// FR-5: picks the farthest point from [points] (chronological, all relative
/// to [anchor]) that a smooth distribution (FR-6) can reach without pushing
/// any intermediate point past its own `hardFloor`, shrinking down to the
/// nearest point if necessary (worst case, always feasible since there are no
/// intermediate points left to violate).
///
/// Called both for a run that's actually starting (real anchor) and,
/// hypothetically, once per day from [planGapOrRunStartDay] with today's
/// current value as anchor, to determine what target it must check against.
///
/// No separate "same direction as anchor" pre-filter: `hardFloor` is always
/// just an upper bound (FR-2), never a required direction of movement, so the
/// per-point violation check below already fully captures FR-5's "shifts no
/// intermediate point past its own `hardFloor`" requirement on its own. An explicit
/// anchor-relative direction filter was tried and removed - once a run is
/// already partway through (anchor is no longer the run's original start,
/// but yesterday's actual, already-progressed value, per FR-8's daily
/// re-derivation), a genuinely non-violated intermediate point can end up on
/// the "wrong side" of a drifted anchor by raw value alone, which a direction
/// filter would wrongly reject even though nothing is actually violated.
///
/// docs/TODO.md T-206: needs the zone's rules [offsetAt] - ΔT is taken on
/// the readings of [anchor] and each point, and the violation check resolves
/// the curve's reading by R_plan before comparing it with the point's
/// instant.
HardFloorPoint groupTarget({
  required DateTime anchor,
  required List<HardFloorPoint> points,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) =>
    _groupTargetFromReading(
      anchorReading: _reading(anchor, offsetAt),
      points: points,
      maxDailyDelta: maxDailyDelta,
      offsetAt: offsetAt,
    );

/// The result of a single day's FR-7 decision: [value] is the day's computed
/// wake time, [overrunNotificationNeeded] mirrors FR-6's flag (only ever true
/// when today turned out to be the first day of a newly-started run).
class GapOrRunStartResult {
  const GapOrRunStartResult({
    required this.value,
    required this.overrunNotificationNeeded,
  });

  final DateTime value;
  final bool overrunNotificationNeeded;
}

/// FR-7 in reading space: [GapOrRunStartResult.value] is the day's planned
/// READING, not yet resolved.
GapOrRunStartResult _planGapOrRunStartDayReading({
  required DateTime vReading,
  required List<HardFloorPoint> remainingPoints,
  required TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) {
  GapOrRunStartResult gapDay() => GapOrRunStartResult(
        value: _gapDayDriftReading(
            vReading: vReading,
            preferredWakeUpTime: preferredWakeUpTime,
            maxDailyDelta: maxDailyDelta),
        overrunNotificationNeeded: false,
      );

  if (remainingPoints.isEmpty) return gapDay();

  final grouped = _groupTargetFromReading(
    anchorReading: vReading,
    points: remainingPoints,
    maxDailyDelta: maxDailyDelta,
    offsetAt: offsetAt,
  );
  final f = _reading(grouped.value, offsetAt);

  // FR-2, and that's the whole point of the word "upper bound"
  // (docs/TODO.md T-132): a `hardFloor` that is NOT earlier than today's
  // value demands nothing. Someone who gets up at 06:45 has long since
  // satisfied an appointment at 11:00 - there's no reason to sleep in for
  // it, and certainly none to blow `maxDailyDelta` for it.
  //
  //   FR-2: "The planned value may be earlier (ALWAYS allowed), but
  //          never later."
  //   FR-5: "`hardFloor` is exclusively an upper bound (FR-2), NEVER a
  //          directional requirement."
  //
  // That is exactly what the run used to get wrong: it treated every point
  // as a target, even a later one, and pulled the wake time up toward it. On
  // a real calendar this looked like: 06:45 -> 08:00 -> 11:00, with
  // `maxDailyDelta` of 30 minutes and a `preferredWakeUpTime` of 07:00.
  //
  // Toward later, the wake time is moved exclusively by FR-4's drift toward
  // `preferredWakeUpTime`, bounded by `maxDailyDelta`. The day's upper bound
  // still applies - but as a cap (the capping in `computeWeekPlan`), not as
  // a pull.
  //
  // FR-5's warning against a "directional filter" is preserved: the points
  // are NOT removed from `remainingPoints`, so they still take part in
  // `groupTarget`'s violation check. They are only excluded as a *target*.
  if (_wallClockDelta(vReading, f) >= Duration.zero ||
      _capOnlyOnItsDate(vReading, grouped, offsetAt)) {
    return gapDay();
  }

  // FR-7: N_Rest = N_F - i. `grouped.dayOffset` is v-relative (the genuine
  // calendar-day distance from `v` to F - groupTarget/distribute need it that
  // way for correct date placement, see groupTarget's doc comment), i.e. it
  // *is* N_F, not N_Rest. `i` is always exactly 1 here: `v` is always exactly
  // the day before "today" (planGapOrRunStartDay only ever decides the single
  // day right after v - see computeWeekPlan's call site), so
  // N_Rest = N_F - 1 = grouped.dayOffset - 1. (Found as a real, previously
  // undetected bug: the isolated tests (test/scheduling_v2_test.dart)
  // passed with the buggy `nRest = grouped.dayOffset` because their own
  // dayOffset inputs were themselves off by one in the same direction,
  // canceling the error out for a single-day decision - only
  // computeWeekPlan's genuinely v-relative dayOffset construction across a
  // real multi-day run exposed it.)
  final nRest = grouped.dayOffset - 1;
  // No separate "N_Rest <= 1" early-exit to plain FR-4 here: that would
  // incorrectly abandon an already-established, still-valid run (see
  // groupTarget's doc comment for the matching correction). N_Rest >= 1
  // always (remainingPoints only ever holds points strictly ahead of today),
  // so the feasibility check below is well-defined for every case; FR-6's
  // own N=1 single-day-jump exemption still applies unconditionally inside
  // distribute() whenever it actually gets called with n=1.

  // Reuses distribute()'s own (wall-clock-only, see distribute()'s doc
  // comment) overrun detection, rather than duplicating that arithmetic here
  // - "feasible" means "a fresh N_Rest-day distribute() from candidate to F
  // would not need to exceed maxDailyDelta". Readings only, nothing resolved
  // inside the bisection below (docs/TODO.md T-206): feasibility is ΔT and n.
  //
  // docs/TODO.md T-139: and against EVERY remaining point, not only F. F is
  // only the farthest point a smooth curve from TODAY'S value can reach; a
  // nearer, stricter point between today and F still has to be reachable
  // from the candidate within maxDailyDelta per day. Checked against F alone,
  // a drift toward a later preferredWakeUpTime could spend exactly the reserve
  // that point needed (anchor 05:04, maxDailyDelta 60, preferredWakeUpTime
  // 06:30, hardFloors 04:36 in two days and 03:42 in three: the drift to 05:42
  // passed F's check and left a 66-minute step into 04:36).
  //
  // Checked in groupTarget's frame, not on readings with FR-1's wrap: the
  // fastest descent from the candidate is placed exactly where groupTarget
  // places its curve (the candidate's reading date + the days left), resolved,
  // and compared with the point's instant. A first version compared
  // readings: where the anchor's reading lies on the date before its day (a
  // night shift's 22:00 alarm for a 00:00 shift, T-118b), a daytime
  // appointment two days on then read as "11 hours earlier, one day left",
  // nothing was feasible, and the run started at once - up to 35 minutes
  // earlier for no gain (T-139 review, differential case #22).
  //
  // Only for a point FR-5 could make a target from today's anchor - one FR-1
  // reads as EARLIER than yesterday's value (T-139 review B1). A point more
  // than 12 hours earlier by the clock reads as later under FR-1's wrap: FR-5
  // never aims at it, so a run started on its account would aim at some other
  // point and not help it, while suppressing the FR-4 drift that would (a
  // night-to-day shift change: 21:46 with a 07:43 appointment five days on).
  // The set is fixed by the anchor, not by each candidate - otherwise a drift
  // that brings such a point within 12 hours would veto itself, and the
  // value would stall exactly 12 hours from it. Once the anchor itself has
  // come within 12 hours, the point is a target and vetoes like any other;
  // until then it is only its own day's cap (FR-2).
  final targetable = [
    for (final point in remainingPoints)
      if (_wallClockDelta(vReading, _reading(point.value, offsetAt))
              .isNegative &&
          !_capOnlyOnItsDate(vReading, point, offsetAt))
        point,
  ];
  bool reachesEveryPoint(DateTime candidate) {
    for (final point in targetable) {
      final daysLeft = point.dayOffset - 1;
      final fastest = resolvePlannedClockTime(
          _readingDaysLater(candidate, daysLeft)
              .subtract(maxDailyDelta * daysLeft),
          offsetAt);
      if (fastest.isAfter(point.value)) return false;
    }
    return true;
  }

  // F itself is one of the remaining points, so `reachesEveryPoint` already
  // decides the side that matters - can today's value still come down to F
  // in time - in the same frame as every other point (T-139 review: the
  // time-of-day check alone gave a night shift's evening anchor one day less
  // than groupTarget's frame and started runs that were not yet needed).
  // What remains of the time-of-day check is the other side: a drift toward
  // an earlier preferredWakeUpTime may not overshoot F by more than the
  // remaining days can bring back.
  bool overshootsF(DateTime candidate) {
    final delta = _wallClockDelta(candidate, f);
    return !delta.isNegative &&
        delta.inMicroseconds > maxDailyDelta.inMicroseconds * nRest;
  }

  bool feasible(DateTime candidate) =>
      reachesEveryPoint(candidate) && !overshootsF(candidate);

  // Holding means today's reading at yesterday's time of day: the date
  // matters to `reachesEveryPoint`, which places the descent on real dates.
  if (!feasible(_readingDaysLater(vReading, 1))) {
    // Already violated by mere holding: today is day 1 of the run.
    final n = nRest + 1; // FR-7: N = N_F - i + 1, today-relative = nRest + 1.
    final curve = _distributeReadings(
        anchor: vReading, target: f, n: n, maxDailyDelta: maxDailyDelta);
    return GapOrRunStartResult(
      value: curve.valuesByDayOffset[1]!,
      overrunNotificationNeeded: curve.overrunNotificationNeeded,
    );
  }

  final drifted = _gapDayDriftReading(
      vReading: vReading,
      preferredWakeUpTime: preferredWakeUpTime,
      maxDailyDelta: maxDailyDelta);
  if (feasible(drifted)) {
    return GapOrRunStartResult(
        value: drifted, overrunNotificationNeeded: false);
  }

  // Only the full preferredWakeUpTime step violates it: cap at the largest
  // amount that still satisfies the condition (binary search, since
  // |V+d*sign - F| is convex as a function of d, satisfied at d=0, violated
  // at d=fullStep). Work happens exclusively in wall-clock differences (not
  // `drifted.difference(v)`, which would include the date advance to
  // v.day+1 introduced by the drift) - candidates are built accordingly on
  // the real following day, not via `v.add(...)` (which would wrongly stay
  // on v's own date).
  final today = _readingDaysLater(vReading, 1);
  final fullStep = _wallClockDelta(vReading, drifted);
  final fullStepMicros = fullStep.inMicroseconds.abs();
  final sign = fullStep.isNegative ? -1 : 1;
  var lo = 0;
  var hi = fullStepMicros;
  while (hi - lo > 1) {
    final mid = lo + (hi - lo) ~/ 2;
    final candidate = today.add(Duration(microseconds: sign * mid));
    if (feasible(candidate)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return GapOrRunStartResult(
    value: today.add(Duration(microseconds: sign * lo)),
    overrunNotificationNeeded: false,
  );
}

/// FR-7: decides whether today is still a gap day (FR-4 applies, possibly
/// capped) or already the first day of a run (FR-6 applies directly).
///
/// [remainingPoints] must have `dayOffset` relative to **today** (tomorrow is
/// day 1) - rebased fresh by the caller on every daily replanning pass, not
/// carried over from a fixed historical anchor. This function itself never
/// needs to know "which absolute day" today is.
///
/// docs/TODO.md T-206: [v] and the result's value are instants; the decision
/// is made on readings under [offsetAt] (FR-1), and the value is resolved by
/// R_plan once, at the end.
GapOrRunStartResult planGapOrRunStartDay({
  required DateTime v,
  required List<HardFloorPoint> remainingPoints,
  required TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
  required ZoneOffsetAt offsetAt,
}) {
  final planned = _planGapOrRunStartDayReading(
    vReading: _reading(v, offsetAt),
    remainingPoints: remainingPoints,
    preferredWakeUpTime: preferredWakeUpTime,
    maxDailyDelta: maxDailyDelta,
    offsetAt: offsetAt,
  );
  return GapOrRunStartResult(
    value: resolvePlannedClockTime(planned.value, offsetAt),
    overrunNotificationNeeded: planned.overrunNotificationNeeded,
  );
}

/// FR-9: the rolling safety-valve counter, evaluated once per day for the day
/// that just concluded. Resets to 0 on any real `hardFloor` day; otherwise
/// increments by 1. Today itself is never passed in until it has concluded -
/// callers must not call this speculatively for still-future window days.
int updateGapDayCounter({
  required int previousCounter,
  required bool dayHadRealHardFloor,
}) {
  return dayHadRealHardFloor ? 0 : previousCounter + 1;
}

/// FR-10's planned READING for [day]: its calendar date at
/// [preferredWakeUpTime].
DateTime _coldStartReading(DateTime day, TimeOfDay preferredWakeUpTime) =>
    DateTime.utc(day.year, day.month, day.day, preferredWakeUpTime.hour,
        preferredWakeUpTime.minute);

/// FR-10: values for [days] (chronological, all strictly before the first
/// real `hardFloor` point) when there is no established
/// `lastEffectiveWakeTime` yet - the very first planning run ever. The first
/// real `hardFloor` day itself is not part of [days]; it's handled directly
/// by FR-2 and becomes the new anchor for whatever follows (computeWeekPlan).
/// [days] are **device-local calendar dates** (date markers - only their
/// year/month/day are read), and [preferredWakeUpTime] is a bare device-local time
/// (FR-3), so producing an absolute instant (FR-1) needs the zone's rules -
/// same reason as in [applyGapDayDrift], see `docs/TODO.md` T-61. Each day is
/// resolved by R_plan with its own rules (T-206).
Map<DateTime, DateTime?> coldStart({
  required List<DateTime> days,
  required TimeOfDay? preferredWakeUpTime,
  required ZoneOffsetAt offsetAt,
}) {
  return {
    for (final day in days)
      day: preferredWakeUpTime == null
          ? null
          : resolvePlannedClockTime(
              _coldStartReading(day, preferredWakeUpTime), offsetAt),
  };
}

/// FR-8: the result of planning [window]. [overrunNotificationNeeded] and
/// [safetyValveTriggered] mirror FR-6's and FR-9's respective notification
/// flags - the caller (`replan`, which hands them to
/// `reportReplanNotifications`) decides how/whether to actually notify.
class WeekPlanResult {
  const WeekPlanResult({
    required this.valuesByDay,
    required this.overrunNotificationNeeded,
    required this.safetyValveTriggered,
    required this.instantAnchoredDays,
    this.plannedClockTimes = const {},
  });

  final Map<DateTime, DateTime?> valuesByDay;
  final bool overrunNotificationNeeded;
  final bool safetyValveTriggered;

  /// Days whose value came **directly from a real `hardFloor`** and is
  /// therefore instant-anchored: it denotes a fixed real moment (the
  /// appointment), so FR-16 must leave it alone when the device's UTC offset
  /// changes - "only the local display changes". Every other planned day
  /// is wall-clock-anchored (`preferredWakeUpTime`/curve) and has to keep its
  /// planned clock time instead ([plannedClockTimes]). Checkpoint 2
  /// (`runTimezoneCheckpoint2`) cannot tell the two apart on its own - it has
  /// no calendar access by design - so this is persisted alongside the values.
  final Set<DateTime> instantAnchoredDays;

  /// docs/TODO.md T-206 (T206-R9, FR-3): window day -> the planned clock time
  /// its wall-clock-anchored value was planned as - a UTC-tagged READING, not
  /// an instant. Invariants: an entry exists exactly for the days with a
  /// value that are not instant-anchored (P1), and that value is exactly
  /// `resolvePlannedClockTime(entry)` (P2). Needed because a skipped reading
  /// cannot be recovered from its instant (02:30 on a spring-forward day
  /// resolves to 03:00, and 03:00 is what the clock then shows).
  final Map<DateTime, DateTime> plannedClockTimes;
}

/// FR-9's threshold: "Once the counter reaches **>= 7**, automatic
/// advancement is stopped and the user is notified."
///
/// Named this way because it's checked in two places (with and without an
/// anchor) and the two must not diverge - a silent change to 6 would switch
/// the alarm off a day too early, and until 2026-09 no test would have
/// noticed: the suite only called `computeWeekPlan` with 0, 7, and 42, never
/// with 6 (docs/TODO.md T-107).
const int gapDayValveThreshold = 7;

/// FR-8: plans every day in [window] (chronological), the big integration
/// step tying FR-2/FR-4/FR-5/FR-6/FR-7/FR-9/FR-10 together.
///
/// [gapDayCounter] must already reflect every already-concluded day up to
/// today (FR-9) - this function never increments it for days still being
/// planned, only ever consults it.
WeekPlanResult computeWeekPlan({
  required List<DateTime> window,
  required DateTime? lastEffectiveWakeTime,
  // docs/TODO.md T-206 (T206-R10, FR-3): the planned clock time the anchor's
  // value was planned as, if one is stored. Used as the anchor's reading only
  // if it is consistent with the anchor - its R_plan equals
  // [lastEffectiveWakeTime] in whole milliseconds, the stored precision -
  // otherwise the anchor's own reading L(v) is. `lastEffectiveWakeTime` stays
  // the only source of WHICH value rang.
  DateTime? lastEffectiveClockTime,
  required List<Meeting> allEvents,
  // docs/TODO.md T-206 (T206-R1): the device zone's rules. Every day is
  // planned with the rules for that day, every appointment assigned with the
  // rules at its own instant.
  required ZoneOffsetAt offsetAt,
  required Duration durationToWakeUp,
  // docs/TODO.md T-52.3: a callback rather than one `Duration` for the whole
  // window - "duration to get ready" can differ per weekday (an override the
  // AppState/UI layer resolves; see `replan.dart`'s call site), and a single
  // week's window can span every weekday in one call.
  required Duration Function(DateTime day) durationToGetReadyForDay,
  required TimeOfDay? preferredWakeUpTime,
  required Duration maxDailyDelta,
  required int gapDayCounter,
  // docs/TODO.md T-52.1: when false, a day with no calendar entry of its own
  // gets no alarm at all, instead of FR-4's drift/hold. Applied as a mask
  // over the algorithm's normal output (see the two `return`s below) rather
  // than folded into the drift math itself, so every existing invariant
  // (anchor propagation, FR-5/6/7/9) stays exactly as it was for the days
  // that DO have an appointment - masking cannot change how those are
  // computed, only whether a day *without* one is allowed to keep a value.
  required bool scheduleOnGapDays,
}) {
  DateTime resolve(DateTime clockTime) =>
      resolvePlannedClockTime(clockTime, offsetAt);
  DateTime readingOf(DateTime instant) => _reading(instant, offsetAt);

  final hardFloorByDay = <DateTime, DateTime>{};
  for (final day in window) {
    final hf = hardFloor(
      day: day,
      allEvents: allEvents,
      offsetAt: offsetAt,
      durationToWakeUp: durationToWakeUp,
      durationToGetReady: durationToGetReadyForDay(day),
    );
    if (hf != null) hardFloorByDay[day] = hf;
  }

  final valuesByDay = <DateTime, DateTime?>{};
  final instantAnchoredDays = <DateTime>{};
  final plannedClockTimes = <DateTime, DateTime>{};
  var overrunNotificationNeeded = false;
  var safetyValveTriggered = false;

  // FR-10 for [days]: each day's planned clock time and its value.
  void addColdStart(List<DateTime> days) {
    for (final day in days) {
      if (preferredWakeUpTime == null) {
        valuesByDay[day] = null;
        continue;
      }
      final clockTime = _coldStartReading(day, preferredWakeUpTime);
      valuesByDay[day] = resolve(clockTime);
      plannedClockTimes[day] = clockTime;
    }
  }

  DateTime? anchor = lastEffectiveWakeTime;
  // docs/TODO.md T-206 (FR-3/FR-4): the READING the anchor stands for - what
  // every shift below is measured from. For a wall-clock-anchored day that
  // is its planned clock time, not the reading its instant shows (which
  // differs for a skipped reading: planned 02:30, rang at 03:00).
  DateTime? anchorReading;
  var startIndex = 0;
  // The real calendar date `anchor`'s value conceptually belongs to - needed
  // to compute each HardFloorPoint's dayOffset as a genuine day-count (not a
  // window-array-index difference, which silently drifts by one once the
  // anchor itself isn't window[0] - see distribute()'s wall-clock-delta fix
  // for why getting this real day-count right matters).
  //
  // docs/TODO.md T-76: that day-count has to be **calendar** arithmetic
  // (`dayMarker`/`dayDistance`), not duration arithmetic. `window`'s entries
  // are device-local date markers, and a local day containing a DST
  // transition is 23 (or 25) hours long, so `difference(...).inDays`
  // under-counted it: two window days got the same dayOffset, which shrank
  // N_Rest, over-steepened the curve, and made groupTarget's violation check
  // compare the wrong day against its hardFloor. See
  // test/scheduling_v2_dst_test.dart.
  late DateTime anchorDay;

  if (anchor == null) {
    // FR-10: cold start.
    final firstRealIndex = window.indexWhere(hardFloorByDay.containsKey);
    if (firstRealIndex == -1) {
      if (scheduleOnGapDays) {
        addColdStart(window);
      } else {
        for (final day in window) {
          valuesByDay[day] = null;
        }
      }
      return WeekPlanResult(
        valuesByDay: valuesByDay,
        overrunNotificationNeeded: false,
        // FR-9's valve reports from this branch too (docs/TODO.md T-107).
        //
        // It used to be hardcoded `false` here, which quietly ended the
        // episode after exactly one day: once the valve has nulled the whole
        // window, the next checkpoint finds `lastEffectiveWakeTime == null`
        // and lands right here - counter still climbing, still nothing
        // planned, but the result claims there is no valve condition.
        // `reportReplanNotifications` reads that as "episode over" and clears
        // `safetyValveNotificationSent`, so a notification that failed on day
        // one is never retried: a permanently silent alarm clock with no
        // message at all, which FR-9's own rationale calls "the wrong
        // outcome".
        //
        // The same expression also covers the case where no anchor ever
        // existed (fresh install, calendar permission granted but no
        // appointments, no preferredWakeUpTime): FR-9 states exactly one exception to
        // "counter >= 7 -> stopped and notified", namely a set
        // `preferredWakeUpTime`. FR-10 governs only the *values* in this branch
        // ("Without: no alarm planned"), never the notification.
        safetyValveTriggered: gapDayCounter >= gapDayValveThreshold &&
            preferredWakeUpTime == null,
        instantAnchoredDays: const {},
        plannedClockTimes: plannedClockTimes,
      );
    }
    addColdStart(window.sublist(0, firstRealIndex));
    anchor = hardFloorByDay[window[firstRealIndex]]!;
    anchorReading = readingOf(anchor);
    valuesByDay[window[firstRealIndex]] = anchor;
    instantAnchoredDays.add(window[firstRealIndex]);
    anchorDay = window[firstRealIndex];
    startIndex = firstRealIndex + 1;
  } else {
    // T206-R10: the stored clock time counts only while it is consistent with
    // the value that rang - compared in whole milliseconds, the precision
    // both are stored in. Any mismatch falls back to the value (FR-3).
    final clockTime = lastEffectiveClockTime;
    anchorReading = clockTime != null &&
            resolve(clockTime).millisecondsSinceEpoch ==
                anchor.millisecondsSinceEpoch
        ? clockTime
        : readingOf(anchor);
    anchorDay = dayMarker(window[startIndex], -1);
  }

  for (var i = startIndex; i < window.length; i++) {
    final day = window[i];
    final ownHardFloor = hardFloorByDay[day];

    // Real hardFloor points strictly after today, rebased relative to
    // `anchorDay` (yesterday's real date) - a genuine day-count, not a
    // window-array-index difference.
    final remaining = <HardFloorPoint>[
      for (var j = i + 1; j < window.length; j++)
        if (hardFloorByDay[window[j]] case final hf?)
          HardFloorPoint(
            dayOffset: dayDistance(window[j], anchorDay),
            value: hf,
          ),
    ];

    if (remaining.isEmpty &&
        ownHardFloor == null &&
        gapDayCounter >= gapDayValveThreshold &&
        // FR-9 "Exception: `preferredWakeUpTime` set" (docs/TODO.md T-78): the valve
        // guards against *blind* extrapolation. A preferredWakeUpTime is an explicit
        // target - FR-4 drifts towards it and stops exactly on it, so the
        // continuation is bounded by construction and there is nothing to
        // guard against. Triggering anyway would be a one-way trapdoor: with
        // every value null, FR-18 removes all future alarms, nothing rings,
        // and without a ring checkpoint the counter can never be reset again
        // (only a real hardFloor day resets it) - a permanently dead alarm
        // clock. Removing the preferredWakeUpTime later re-arms the valve immediately,
        // since the counter itself keeps counting regardless.
        preferredWakeUpTime == null) {
      // FR-9: safety valve - no appointment on this day or on any LATER
      // window day, and already 7 elapsed appointment-free days. Stop
      // auto-continuing. Note what this condition does not require: an
      // appointment on an EARLIER window day does not stop it, so the days
      // after the last in-window appointment are emptied too (the valve's
      // asymmetry, an open spec decision - docs/TODO.md T-121; deliberately
      // unchanged here). No value, so no planned clock time either
      // (T206-R9).
      valuesByDay[day] = null;
      safetyValveTriggered = true;
      continue;
    }

    // The day's planned READING (FR-4's drift/hold, or FR-7's decision) and
    // whether it opens a run that needs FR-6's notification.
    final DateTime plannedReading;
    var runOverrun = false;
    if (remaining.isEmpty) {
      // Here too FR-2's upper bound is a cap, not a target (docs/TODO.md
      // T-132): previously the day's own `hardFloor` was assigned unconditionally,
      // even when it lay LATER than today's value - the user would have slept in
      // for no reason at all.
      plannedReading = _gapDayDriftReading(
          vReading: anchorReading!,
          preferredWakeUpTime: preferredWakeUpTime,
          maxDailyDelta: maxDailyDelta);
    } else {
      final candidate = _planGapOrRunStartDayReading(
        vReading: anchorReading!,
        remainingPoints: remaining,
        preferredWakeUpTime: preferredWakeUpTime,
        maxDailyDelta: maxDailyDelta,
        offsetAt: offsetAt,
      );
      plannedReading = candidate.value;
      runOverrun = candidate.overrunNotificationNeeded;
    }

    // FR-1 (T-206): resolve first, then cap - on instants. FR-2: hardFloor is
    // always an upper bound - today's own (if any) may never be exceeded,
    // even by an otherwise-correct ongoing smooth curve. Capping on readings
    // instead would let a reading in a repeated hour slip past an
    // appointment between its two occurrences.
    final resolved = resolve(plannedReading);
    final clampedToOwnHardFloor =
        ownHardFloor != null && resolved.isAfter(ownHardFloor);
    final DateTime value;
    if (clampedToOwnHardFloor) {
      value = ownHardFloor;
      instantAnchoredDays.add(day);
      // FR-6's reporting duty, which the branch without following points
      // used to skip entirely (docs/TODO.md T-105) and the capped run branch
      // too (T-133). Assigning a day its own hardFloor is a legitimate jump
      // of any size - FR-6 explicitly permits it when the distance is a
      // single day - but the requirement reads "on EVERY excess over
      // maxDailyDelta (N=1 OR distributed) the user is notified once". The
      // N=1 exemption is about not being able to spread the jump, not about
      // staying silent.
      //
      // The everyday case behind this: the wake time has drifted over
      // appointment-free days toward `preferredWakeUpTime`, then an
      // appointment is discovered late. The first working day is then pulled
      // back in one step - measured at 45 minutes against an allowed 30, and
      // the user never heard about it.
      //
      // Same formula as `distribute` uses, so the paths cannot drift apart:
      // ΔT/N > maxDailyDelta, expressed without a division - and ΔT on
      // readings (FR-1, T-206), so a daylight-saving change is no shift.
      final n = dayDistance(day, anchorDay);
      final delta = _wallClockDelta(anchorReading, readingOf(value)).abs();
      if (n >= 1 && delta.inMicroseconds > maxDailyDelta.inMicroseconds * n) {
        overrunNotificationNeeded = true;
      }
      anchorReading = readingOf(value);
    } else {
      value = resolved;
      plannedClockTimes[day] = plannedReading;
      anchorReading = plannedReading;
    }

    valuesByDay[day] = value;
    anchorDay = day;
    if (runOverrun) overrunNotificationNeeded = true;
  }

  if (scheduleOnGapDays) {
    return WeekPlanResult(
      valuesByDay: valuesByDay,
      overrunNotificationNeeded: overrunNotificationNeeded,
      safetyValveTriggered: safetyValveTriggered,
      instantAnchoredDays: instantAnchoredDays,
      plannedClockTimes: plannedClockTimes,
    );
  }
  // T-52.1's mask: a day without an appointment of its own loses its value,
  // and its planned clock time with it (T206-R9).
  return WeekPlanResult(
    valuesByDay: {
      for (final entry in valuesByDay.entries)
        entry.key: hardFloorByDay.containsKey(entry.key) ? entry.value : null,
    },
    overrunNotificationNeeded: overrunNotificationNeeded,
    safetyValveTriggered: safetyValveTriggered,
    instantAnchoredDays:
        instantAnchoredDays.where(hardFloorByDay.containsKey).toSet(),
    plannedClockTimes: {
      for (final entry in plannedClockTimes.entries)
        if (hardFloorByDay.containsKey(entry.key)) entry.key: entry.value,
    },
  );
}

/// FR-16: reinterprets a wall-clock-anchored [value] (a "carried-forward
/// intermediate value" - the actual output of FR-4/FR-6/FR-7, computed while
/// [oldOffset] was in effect) so its **local wall-clock reading stays the
/// same digits**, now read under [newOffset] instead (the alarm-clock
/// convention: "7:00" stays "7:00", just in the new zone) - rather than
/// preserving the absolute instant (which would silently shift the local
/// reading whenever the offset changes). Comparing offsets (not zone names)
/// makes this identical for a genuine relocation and a plain DST transition
/// (FR-16's own point).
///
/// **Never** call this for an `hardFloor`-derived (instant-based, FR-1/FR-2)
/// value - those stay unchanged; only the local *display* of an unchanged
/// instant differs after an offset change. Deciding which of a day's
/// `pendingDayValues` entries are wall-clock-anchored (this applies) versus
/// hardFloor-derived (this must not be applied) is the caller's job
/// (`runTimezoneCheckpoint2`), not this pure function's - `preferredWakeUpTime` itself is never an
/// input here either, since it already carries no zone of its own (FR-3) and
/// so needs no reinterpretation at all.
///
/// docs/TODO.md T-206: since then used only by Checkpoint 2's LEGACY branch -
/// a plan stored by a version before T-206, with no `pendingDayClockTimes` at
/// all.
/// A plan with planned clock times is re-resolved by R_plan instead, which
/// leaves a value planned with a DST change's own rules alone (this shift
/// would move it by the DST difference).
DateTime reinterpretForNewOffset({
  required DateTime value,
  required Duration oldOffset,
  required Duration newOffset,
}) {
  return value.add(oldOffset - newOffset);
}
