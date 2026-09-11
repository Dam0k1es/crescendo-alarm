// Scheduling-Logik v2 (docs/scheduling-v2-spec.md). Pure functions only - no
// AppState, no BuildContext, no plugin access, so every function here is
// directly unit-testable without mocks (see test/scheduling_v2_test.dart).
//
// Convention (spec, Phase 0): "Instant" is represented as a plain [DateTime];
// "wunschzeit" as a [TimeOfDay]; day windows as plain integer day-offsets.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart' show Meeting;

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
int _timeOfDayMicros(DateTime t) =>
    ((t.hour * 60 + t.minute) * 60 + t.second) * 1000000 + t.microsecond;

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
Duration _wallClockDelta(DateTime anchor, DateTime target) {
  var deltaMicros = _timeOfDayMicros(target) - _timeOfDayMicros(anchor);
  const dayMicros = 24 * 60 * 60 * 1000000;
  const halfDayMicros = dayMicros ~/ 2;
  if (deltaMicros > halfDayMicros) deltaMicros -= dayMicros;
  if (deltaMicros <= -halfDayMicros) deltaMicros += dayMicros;
  return Duration(microseconds: deltaMicros);
}

/// Builds a `DateTime` on [reference]'s year/month with the given [day]/time
/// components, preserving [reference]'s UTC-ness (`DateTime(...)` always
/// builds a **local** instant regardless of its inputs' own origin - naively
/// reusing it on a UTC [reference] silently reinterprets its wall-clock
/// components in the host's local offset instead, corrupting the real instant
/// whenever that offset isn't zero).
DateTime _dateTimeLike(
  DateTime reference, {
  required int day,
  required int hour,
  required int minute,
  int second = 0,
  int millisecond = 0,
  int microsecond = 0,
}) {
  return reference.isUtc
      ? DateTime.utc(reference.year, reference.month, day, hour, minute,
          second, millisecond, microsecond)
      : DateTime(reference.year, reference.month, day, hour, minute, second,
          millisecond, microsecond);
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
DistributionResult distribute({
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
    final dayI = _dateTimeLike(
      anchor,
      day: anchor.day + i,
      hour: anchor.hour,
      minute: anchor.minute,
      second: anchor.second,
      millisecond: anchor.millisecond,
      microsecond: anchor.microsecond,
    );
    values[i] = dayI.add(Duration(microseconds: sign * stepMicros));
  }

  final overrunNotificationNeeded =
      deltaMicros > maxDailyDelta.inMicroseconds * n;

  return DistributionResult(
    valuesByDayOffset: values,
    overrunNotificationNeeded: overrunNotificationNeeded,
  );
}

/// The device-local reading of an absolute [instant] under [deviceUtcOffset],
/// carried in a UTC-tagged `DateTime` whose year/month/day/hour/minute are the
/// values a clock in that zone would show. Mirrors [eventsForDay]'s own
/// conversion, and is deliberately explicit rather than `toLocal()` so nothing
/// depends on the host machine's zone (FR-2 "Testbarkeit").
DateTime _localReading(DateTime instant, Duration deviceUtcOffset) =>
    instant.toUtc().add(deviceUtcOffset);

/// Inverse of [_localReading]: turns a device-local reading back into the
/// absolute instant it denotes.
DateTime _instantOf(DateTime localReading, Duration deviceUtcOffset) =>
    localReading.subtract(deviceUtcOffset);

/// FR-4, isolated from FR-7s cap: computes **today**'s (the day after `v`'s own
/// **device-local** date - the day actually being planned) wake time by
/// drifting `v` towards [wunschzeit] by at most [maxDailyDelta], stopping
/// exactly at [wunschzeit] rather than overshooting. Holds at `v`'s clock
/// reading (on today's date) if [wunschzeit] is null or already reached.
///
/// [v] and the return value are absolute instants (FR-1); [wunschzeit] is a
/// bare device-local `TimeOfDay` with no date or zone of its own (FR-3). That
/// mismatch is exactly why [deviceUtcOffset] is needed here (`docs/TODO.md`
/// T-61): combining wunschzeit's digits with `v`'s *raw* fields would compare a
/// device-local wall clock against a UTC one and drift by the offset on any
/// device outside UTC+0. Everything below therefore happens in the local
/// reading, and only the result is converted back to an instant.
///
/// [distribute]/[groupTarget] need no offset by contrast - they only ever
/// compare two instants in the same frame, and their `Tag_i` date advance
/// yields the identical instant whether computed in the local or the raw frame.
DateTime applyGapDayDrift({
  required DateTime v,
  required TimeOfDay? wunschzeit,
  required Duration maxDailyDelta,
  required Duration deviceUtcOffset,
}) {
  final vLocal = _localReading(v, deviceUtcOffset);
  final todayLocal = DateTime.utc(
    vLocal.year,
    vLocal.month,
    vLocal.day + 1,
    vLocal.hour,
    vLocal.minute,
    vLocal.second,
    vLocal.millisecond,
    vLocal.microsecond,
  );
  if (wunschzeit == null) return _instantOf(todayLocal, deviceUtcOffset);

  final targetLocal = DateTime.utc(todayLocal.year, todayLocal.month,
      todayLocal.day, wunschzeit.hour, wunschzeit.minute);
  final distance = _wallClockDelta(vLocal, targetLocal);
  if (distance == Duration.zero) {
    return _instantOf(todayLocal, deviceUtcOffset);
  }

  final step = distance.abs() < maxDailyDelta ? distance.abs() : maxDailyDelta;
  return _instantOf(
      todayLocal.add(distance.isNegative ? -step : step), deviceUtcOffset);
}

/// FR-2: which of [allEvents] fall on [day], bucketed by [deviceUtcOffset] -
/// **never** by an event's own zone (that's already baked into `.from` as an
/// absolute instant by existing, unchanged conversion code, see FR-2
/// "Termin-eigene Zeitzone"). [deviceUtcOffset] is an explicit parameter
/// rather than `DateTime.toLocal()` so this stays deterministic regardless of
/// the host machine's own configured timezone (see FR-2 "Testbarkeit").
List<Meeting> eventsForDay(
  DateTime day, {
  required List<Meeting> allEvents,
  required Duration deviceUtcOffset,
}) {
  return allEvents.where((event) {
    final local = event.from.toUtc().add(deviceUtcOffset);
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }).toList();
}

/// FR-2: the upper bound ("not later than") for [day], or null if [day] is a
/// Lückentag (only all-day events, or none at all).
DateTime? hardFloor({
  required DateTime day,
  required List<Meeting> allEvents,
  required Duration deviceUtcOffset,
  required Duration durationToWakeUp,
  required Duration durationToGetReady,
}) {
  final dayEvents = eventsForDay(
    day,
    allEvents: allEvents,
    deviceUtcOffset: deviceUtcOffset,
  );
  final nonAllDay = dayEvents.where((event) => !event.isAllDay);
  if (nonAllDay.isEmpty) return null;

  final earliest =
      nonAllDay.reduce((a, b) => a.from.isBefore(b.from) ? a : b);
  // docs/TODO.md T-61: normalise the frame. `Meeting.from` is what
  // `device_calendar` produced - a `TZDateTime` in the **event's own** zone,
  // whose `.hour`/`.minute` are that zone's digits. Every other value in this
  // layer is UTC-tagged, and `_wallClockDelta` compares digit fields, so
  // handing the event's own frame onward made ΔT wrong by the device offset on
  // any device outside UTC+0 (empirically: a 09:00 Berlin event produced a
  // wake time two hours late). `.toUtc()` keeps the exact same real moment
  // (FR-1/FR-16: the appointment does not move) and puts it in the one frame
  // the whole layer shares.
  return earliest.from
      .toUtc()
      .subtract(durationToWakeUp)
      .subtract(durationToGetReady);
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
/// per-point violation check below already fully captures FR-5's "keinen
/// Zwischenpunkt verletzen" requirement on its own. An explicit
/// anchor-relative direction filter was tried and removed - once a run is
/// already partway through (anchor is no longer the run's original start,
/// but yesterday's actual, already-progressed value, per FR-8's daily
/// re-derivation), a genuinely non-violated intermediate point can end up on
/// the "wrong side" of a drifted anchor by raw value alone, which a direction
/// filter would wrongly reject even though nothing is actually violated.
HardFloorPoint groupTarget({
  required DateTime anchor,
  required List<HardFloorPoint> points,
  required Duration maxDailyDelta,
}) {
  assert(points.isNotEmpty, 'groupTarget needs at least one real hardFloor point');

  // FR-5 step 2: a ΔT=0 point (same wall-clock reading as the anchor - real
  // calendar dates necessarily differ, since points are always strictly ahead
  // of the anchor) ends its own run immediately and "wird nie mit einem
  // Folgepunkt zusammengefasst".
  //
  // That sentence carries no positional caveat, so the run is capped at the
  // FIRST such point wherever it sits - not only when it happens to be
  // points.first. The spec's own worked example puts it at position 1, which
  // is exactly the case a `points.first` check already covers; an independent
  // review found the same wording violated from position 2 onwards
  // (docs/TODO.md T-104).
  //
  // Capping rather than returning: step 1's shrinking still applies below the
  // cap. A ΔT=0 target yields a flat curve, and a flat curve can perfectly
  // well violate a stricter intermediate point - then t_m has to shrink
  // further, exactly as for any other target.
  final zeroDeltaIndex = points.indexWhere(
      (p) => _wallClockDelta(anchor, p.value) == Duration.zero);
  final candidates =
      zeroDeltaIndex == -1 ? points : points.sublist(0, zeroDeltaIndex + 1);
  for (var m = candidates.length; m >= 1; m--) {
    final target = candidates[m - 1];
    final curve = distribute(
      anchor: anchor,
      target: target.value,
      n: target.dayOffset,
      maxDailyDelta: maxDailyDelta,
    );

    var violated = false;
    for (var j = 0; j < m - 1; j++) {
      final intermediate = candidates[j];
      final interpolated = curve.valuesByDayOffset[intermediate.dayOffset]!;
      if (interpolated.isAfter(intermediate.value)) {
        violated = true;
        break;
      }
    }
    if (!violated) return target;
  }

  // Unreachable: m=1 has no intermediate points to violate, so the loop
  // above always returns by then.
  return candidates.first;
}

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

/// FR-7: decides whether today is still a gap day (FR-4 applies, possibly
/// capped) or already the first day of a run (FR-6 applies directly).
///
/// [remainingPoints] must have `dayOffset` relative to **today** (tomorrow is
/// day 1) - rebased fresh by the caller on every daily replanning pass, not
/// carried over from a fixed historical anchor. This function itself never
/// needs to know "which absolute day" today is.
GapOrRunStartResult planGapOrRunStartDay({
  required DateTime v,
  required List<HardFloorPoint> remainingPoints,
  required TimeOfDay? wunschzeit,
  required Duration maxDailyDelta,
  required Duration deviceUtcOffset,
}) {
  GapOrRunStartResult gapDay() => GapOrRunStartResult(
        value: applyGapDayDrift(
            v: v,
            wunschzeit: wunschzeit,
            maxDailyDelta: maxDailyDelta,
            deviceUtcOffset: deviceUtcOffset),
        overrunNotificationNeeded: false,
      );

  if (remainingPoints.isEmpty) return gapDay();

  final grouped = groupTarget(
    anchor: v,
    points: remainingPoints,
    maxDailyDelta: maxDailyDelta,
  );
  final f = grouped.value;
  // FR-7: N_Rest = N_F - i. `grouped.dayOffset` is v-relative (the genuine
  // calendar-day distance from `v` to F - groupTarget/distribute need it that
  // way for correct date placement, see groupTarget's doc comment), i.e. it
  // *is* N_F, not N_Rest. `i` is always exactly 1 here: `v` is always exactly
  // the day before "today" (planGapOrRunStartDay only ever decides the single
  // day right after v - see computeWeekPlan's call site), so
  // N_Rest = N_F - 1 = grouped.dayOffset - 1. (Found as a real, previously
  // undetected bug: the isolated tests below happened to pass with the buggy
  // `nRest = grouped.dayOffset` because their own dayOffset inputs were
  // themselves off by one in the same direction, canceling the error out for
  // a single-day decision - only computeWeekPlan's genuinely v-relative
  // dayOffset construction across a real multi-day run exposed it.)
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
  // would not need to exceed maxDailyDelta".
  bool feasible(DateTime candidate) => !distribute(
        anchor: candidate,
        target: f,
        n: nRest,
        maxDailyDelta: maxDailyDelta,
      ).overrunNotificationNeeded;

  if (!feasible(v)) {
    // Bereits beim bloßen Halten verletzt: heute ist Tag 1 des Runs.
    final n = nRest + 1; // FR-7: N = N_F - i + 1, today-relative = nRest + 1.
    final curve = distribute(anchor: v, target: f, n: n, maxDailyDelta: maxDailyDelta);
    return GapOrRunStartResult(
      value: curve.valuesByDayOffset[1]!,
      overrunNotificationNeeded: curve.overrunNotificationNeeded,
    );
  }

  final drifted = applyGapDayDrift(
      v: v,
      wunschzeit: wunschzeit,
      maxDailyDelta: maxDailyDelta,
      deviceUtcOffset: deviceUtcOffset);
  if (feasible(drifted)) {
    return GapOrRunStartResult(value: drifted, overrunNotificationNeeded: false);
  }

  // Nur der volle wunschzeit-Schritt verletzt: auf das größtmögliche Maß
  // kappen, das die Bedingung noch erfüllt (binäre Suche, da |V+d*sign - F|
  // als Funktion von d konvex ist und bei d=0 erfüllt, bei d=fullStep verletzt).
  // Gearbeitet wird ausschließlich in Wall-Clock-Differenzen (nicht
  // `drifted.difference(v)`, das die von applyGapDayDrift eingeführte
  // Datums-Fortschreibung um v.day+1 mit einschließen würde) - candidates
  // werden entsprechend auf dem echten Folgetag aufgebaut, nicht via
  // `v.add(...)` (das fälschlich bei v's eigenem Datum bliebe).
  final today = _dateTimeLike(
    v,
    day: v.day + 1,
    hour: v.hour,
    minute: v.minute,
    second: v.second,
    millisecond: v.millisecond,
    microsecond: v.microsecond,
  );
  final fullStep = _wallClockDelta(v, drifted);
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

/// FR-10: values for [days] (chronological, all strictly before the first
/// real `hardFloor` point) when there is no established
/// `lastEffectiveWakeTime` yet - the very first planning run ever. The first
/// real `hardFloor` day itself is not part of [days]; it's handled directly
/// by FR-2 and becomes the new anchor for whatever follows (computeWeekPlan).
/// [days] are **device-local calendar dates** (date markers - only their
/// year/month/day are read), and [wunschzeit] is a bare device-local time
/// (FR-3), so producing an absolute instant (FR-1) needs [deviceUtcOffset] -
/// same reason as in [applyGapDayDrift], see `docs/TODO.md` T-61.
Map<DateTime, DateTime?> coldStart({
  required List<DateTime> days,
  required TimeOfDay? wunschzeit,
  required Duration deviceUtcOffset,
}) {
  return {
    for (final day in days)
      day: wunschzeit == null
          ? null
          : _instantOf(
              DateTime.utc(day.year, day.month, day.day, wunschzeit.hour,
                  wunschzeit.minute),
              deviceUtcOffset),
  };
}

/// FR-8: the result of planning [window]. [overrunNotificationNeeded] and
/// [safetyValveTriggered] mirror FR-6's and FR-9's respective notification
/// flags - the caller (Phase 4) decides how/whether to actually notify.
class WeekPlanResult {
  const WeekPlanResult({
    required this.valuesByDay,
    required this.overrunNotificationNeeded,
    required this.safetyValveTriggered,
    required this.instantAnchoredDays,
  });

  final Map<DateTime, DateTime?> valuesByDay;
  final bool overrunNotificationNeeded;
  final bool safetyValveTriggered;

  /// Days whose value came **directly from a real `hardFloor`** and is
  /// therefore instant-anchored: it denotes a fixed real moment (the
  /// appointment), so FR-16 must leave it alone when the device's UTC offset
  /// changes - "nur die lokale Anzeige ändert sich". Every other planned day
  /// is wall-clock-anchored (`wunschzeit`/curve) and has to keep its local
  /// digits instead, via `reinterpretForNewOffset`. Checkpoint 2
  /// (`runTimezoneCheckpoint2`) cannot tell the two apart on its own - it has
  /// no calendar access by design - so this is persisted alongside the values.
  final Set<DateTime> instantAnchoredDays;
}

/// FR-8: plans every day in [window] (chronological), the big integration
/// step tying FR-2/FR-4/FR-5/FR-6/FR-7/FR-9/FR-10 together.
///
/// [gapDayCounter] must already reflect every already-concluded day up to
/// today (FR-9) - this function never increments it for days still being
/// planned, only ever consults it.
/// FR-9s Schwelle: "Erreicht der Zaehler **>= 7**, wird automatische
/// Fortschreibung gestoppt und der Nutzer benachrichtigt."
///
/// Benannt, weil sie an zwei Stellen geprueft wird (mit und ohne Anker) und
/// die beiden nicht auseinanderlaufen duerfen - eine stille Aenderung auf 6
/// wuerde den Wecker einen Tag zu frueh abschalten, und bis 2026-09 haette
/// kein Test das bemerkt: die Suite rief `computeWeekPlan` nur mit 0, 7 und 42
/// auf, nie mit 6 (docs/TODO.md T-107).
const int gapDayValveThreshold = 7;

WeekPlanResult computeWeekPlan({
  required List<DateTime> window,
  required DateTime? lastEffectiveWakeTime,
  required List<Meeting> allEvents,
  required Duration deviceUtcOffset,
  required Duration durationToWakeUp,
  required Duration durationToGetReady,
  required TimeOfDay? wunschzeit,
  required Duration maxDailyDelta,
  required int gapDayCounter,
}) {
  final hardFloorByDay = <DateTime, DateTime>{};
  for (final day in window) {
    final hf = hardFloor(
      day: day,
      allEvents: allEvents,
      deviceUtcOffset: deviceUtcOffset,
      durationToWakeUp: durationToWakeUp,
      durationToGetReady: durationToGetReady,
    );
    if (hf != null) hardFloorByDay[day] = hf;
  }

  final valuesByDay = <DateTime, DateTime?>{};
  final instantAnchoredDays = <DateTime>{};
  var overrunNotificationNeeded = false;
  var safetyValveTriggered = false;

  DateTime? anchor = lastEffectiveWakeTime;
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
      return WeekPlanResult(
        valuesByDay: coldStart(
            days: window,
            wunschzeit: wunschzeit,
            deviceUtcOffset: deviceUtcOffset),
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
        // message at all, which FR-9's own rationale calls "der falsche
        // Ausgang".
        //
        // The same expression also covers the case where no anchor ever
        // existed (fresh install, calendar permission granted but no
        // appointments, no wunschzeit): FR-9 states exactly one exception to
        // "Zaehler >= 7 -> gestoppt und benachrichtigt", namely a set
        // `wunschzeit`. FR-10 governs only the *values* in this branch
        // ("Ohne: kein Alarm geplant"), never the notification.
        safetyValveTriggered:
            gapDayCounter >= gapDayValveThreshold && wunschzeit == null,
        instantAnchoredDays: const {},
      );
    }
    valuesByDay.addAll(coldStart(
      days: window.sublist(0, firstRealIndex),
      wunschzeit: wunschzeit,
      deviceUtcOffset: deviceUtcOffset,
    ));
    anchor = hardFloorByDay[window[firstRealIndex]];
    valuesByDay[window[firstRealIndex]] = anchor;
    instantAnchoredDays.add(window[firstRealIndex]);
    anchorDay = window[firstRealIndex];
    startIndex = firstRealIndex + 1;
  } else {
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
        // FR-9 "Ausnahme: gesetzte wunschzeit" (docs/TODO.md T-78): the valve
        // guards against *blind* extrapolation. A wunschzeit is an explicit
        // target - FR-4 drifts towards it and stops exactly on it, so the
        // continuation is bounded by construction and there is nothing to
        // guard against. Triggering anyway would be a one-way trapdoor: with
        // every value null, FR-18 removes all future alarms, nothing rings,
        // and without a ring checkpoint the counter can never be reset again
        // (only a real hardFloor day resets it) - a permanently dead alarm
        // clock. Removing the wunschzeit later re-arms the valve immediately,
        // since the counter itself keeps counting regardless.
        wunschzeit == null) {
      // FR-9: safety valve - no future anchor visible anywhere in the
      // window, and already 7 elapsed termin-lose days. Stop auto-continuing.
      valuesByDay[day] = null;
      safetyValveTriggered = true;
      continue;
    }

    if (remaining.isEmpty) {
      final value = ownHardFloor ??
          applyGapDayDrift(
              v: anchor!,
              wunschzeit: wunschzeit,
              maxDailyDelta: maxDailyDelta,
              deviceUtcOffset: deviceUtcOffset);
      if (ownHardFloor != null) {
        instantAnchoredDays.add(day);
        // FR-6's reporting duty, which this branch used to skip entirely
        // (docs/TODO.md T-105). Assigning a day its own hardFloor is a
        // legitimate jump of any size - FR-6 explicitly permits it when the
        // distance is a single day - but the requirement reads "bei JEDER
        // Ueberschreitung von maxDailyDelta (N=1 ODER verteilt) wird der
        // Nutzer einmalig benachrichtigt". The N=1 exemption is about not
        // being able to spread the jump, not about staying silent.
        //
        // Same formula as `distribute` uses, so the two paths cannot drift
        // apart: ΔT/N > maxDailyDelta, expressed without a division.
        final n = dayDistance(day, anchorDay);
        final delta = _wallClockDelta(anchor!, value).abs();
        if (n >= 1 && delta.inMicroseconds > maxDailyDelta.inMicroseconds * n) {
          overrunNotificationNeeded = true;
        }
      }
      valuesByDay[day] = value;
      anchor = value;
      anchorDay = day;
      continue;
    }

    final candidate = planGapOrRunStartDay(
      v: anchor!,
      remainingPoints: remaining,
      wunschzeit: wunschzeit,
      maxDailyDelta: maxDailyDelta,
      deviceUtcOffset: deviceUtcOffset,
    );

    // FR-2: hardFloor is always an upper bound - today's own (if any) may
    // never be exceeded, even by an otherwise-correct ongoing smooth curve.
    final clampedToOwnHardFloor =
        ownHardFloor != null && candidate.value.isAfter(ownHardFloor);
    final value = clampedToOwnHardFloor ? ownHardFloor : candidate.value;
    if (clampedToOwnHardFloor) instantAnchoredDays.add(day);

    valuesByDay[day] = value;
    anchor = value;
    anchorDay = day;
    if (candidate.overrunNotificationNeeded) overrunNotificationNeeded = true;
  }

  return WeekPlanResult(
    valuesByDay: valuesByDay,
    overrunNotificationNeeded: overrunNotificationNeeded,
    safetyValveTriggered: safetyValveTriggered,
    instantAnchoredDays: instantAnchoredDays,
  );
}

/// FR-16: reinterprets a wall-clock-anchored [value] (a "fortgeschriebener
/// Zwischenwert" - the actual output of FR-4/FR-6/FR-7, computed while
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
/// hardFloor-derived (this must not be applied) is the caller's job (Phase 4
/// orchestration), not this pure function's - `wunschzeit` itself is never an
/// input here either, since it already carries no zone of its own (FR-3) and
/// so needs no reinterpretation at all.
DateTime reinterpretForNewOffset({
  required DateTime value,
  required Duration oldOffset,
  required Duration newOffset,
}) {
  return value.add(oldOffset - newOffset);
}
