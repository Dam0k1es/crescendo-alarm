// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

// AppState-aware scheduling-v2 orchestration (docs/scheduling-v2-spec.md,
// "Architecture", "AppState-aware orchestration"). Unlike scheduling_v2.dart,
// these functions DO take AppState directly and perform I/O (calendar reads) -
// but every external dependency (calendar fetch, current time, device offset)
// is injectable, so they stay unit-testable without a device/emulator or a
// mocked plugin channel (see test/replan_test.dart).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart' show DayOfWeek;
import 'package:wakeywakey/models/scheduling/apply_alarms.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/scheduling_v2.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/utils.dart';

typedef FetchEvents = Future<List<Meeting>> Function(DateTime start, DateTime end);

/// FR-6/FR-9/FR-12's respective notification flags, bubbled up from a single
/// `replan()` call - plain data, no side effect: actually showing a
/// notification for any of these is Phase 5's job (platform wiring).
class ReplanResult {
  const ReplanResult({
    required this.overrunNotificationNeeded,
    required this.safetyValveTriggered,
    required this.possiblyMissedAppointment,
  });

  final bool overrunNotificationNeeded;
  final bool safetyValveTriggered;
  final bool possiblyMissedAppointment;
}

/// FR-8: the full daily replanning checkpoint. Never touches `ManualAlarm`s
/// (FR-15) - it only ever reads/writes the `ScheduledAlarm`-related
/// scheduling-v2 fields on [appState].
///
/// Not called directly by app code - `runSchedulingCheckpoint`
/// (`checkpoint.dart`) is the one entry point, and it decides
/// [todayAlreadyRang] from its trigger.
///
/// The day that "just rang" (or, on FR-17's recovery path, today's real
/// calendar date) is [now]'s date - it becomes the new fixed anchor (FR-11:
/// "only the value that has actually been triggered is fixed forever"), and the fresh
/// 7-day window (FR-8: "no extended computation horizon") starts the day
/// after it. If more than one calendar day has elapsed since
/// [AppState.lastProcessedConcludedDay] (e.g. a reboot gap, FR-17), every
/// skipped day in between is walked individually so FR-9's `gapDayCounter` and
/// FR-12's missed-appointment check both reflect each of them, not just the
/// most recent one.
Future<ReplanResult> replan(
  AppState appState, {
  FetchEvents? fetchEvents,
  DateTime Function()? now,
  Duration? deviceUtcOffset,
  bool todayAlreadyRang = false,
}) async {
  // docs/TODO.md T-69: FR-16's Checkpoint 2 writes these fields straight to
  // SharedPreferences from a background isolate, so a live AppState's
  // in-memory copy can be stale. Merging on top of a stale copy silently
  // reverted the checkpoint's reinterpretation, so re-read first.
  await appState.reloadSchedulingStateFromPreferences();

  final nowFn = now ?? DateTime.now;
  final fetch = fetchEvents ??
      (DateTime start, DateTime end) =>
          fetchMeetingsUncached(appState, start, end);
  final currentTime = nowFn();
  final offset = deviceUtcOffset ?? currentTime.timeZoneOffset;

  final today = midnight(currentTime);

  // docs/TODO.md T-75: the day-advance progress marker, deliberately NOT
  // `lastReplanDate` (which only answers FR-17's "did a checkpoint already run
  // today?"). Sharing one field let a harmless early-morning recovery replan
  // consume the marker without advancing it, so the real ring later that same
  // day found nothing to process - the day was lost, FR-9 under-counted and
  // FR-12 never reported. See test/replan_test.dart, group "T-75".
  final lastProcessedDay = appState.lastProcessedConcludedDay;
  final markerDay =
      lastProcessedDay == null ? null : midnight(lastProcessedDay);

  // Which day most recently concluded is a question of STATE, not of the
  // TRIGGER (docs/TODO.md T-114).
  //
  // docs/TODO.md T-71 still holds, but says something different from what
  // this line used to make of it: a checkpoint must not *assume* today has
  // concluded - hence `todayAlreadyRang`. Whether today *has* concluded, by
  // contrast, is what the progress marker says, and if it already points to
  // today, today has demonstrably rung. Ignoring it then turned tomorrow's
  // anchor into a value that never rang - exactly the "second source" that
  // FR-3 warns against ("`lastEffectiveWakeTime` is deliberately not its own
  // field ... as a second source could only drift apart from it"). Measured
  // as a daily step of double to sixfold `maxDailyDelta`.
  //
  // A marker in the FUTURE never counts (`dayDistance <= 0`): it's a
  // device-local digit date with no clamping, and can slip past today's date
  // on a clock correction or a zone change across the date boundary - the
  // same cause as T-109. Without the clamp, the whole window would then count
  // as concluded and nothing at all would be planned anymore.
  //
  // Compared throughout via `dayDistance` rather than `isAfter`: the marker
  // comes locally tagged from the preferences, `currentTime` can be a
  // `tz.TZDateTime`, and an instant comparison of two midnights from
  // different frames is exactly this module's error class (T-61/T-76/T-83).
  final concludedByTrigger =
      todayAlreadyRang ? today : dayMarker(today, -1);
  final lastConcludedDay = (markerDay != null &&
          dayDistance(markerDay, today) <= 0 &&
          dayDistance(markerDay, concludedByTrigger) > 0)
      ? markerDay
      : concludedByTrigger;

  // Here - and only here - is where FR-11's "only the value that has actually
  // been triggered is fixed forever" (docs/TODO.md T-106) actually arises:
  // the window starts after the most recently concluded day, so a concluded
  // day can no longer be recomputed or overwritten at all.
  //
  // In the meantime this guarantee instead lived as a write-lock in the merge
  // further below. Once [lastConcludedDay] started following state (T-114),
  // that was demonstrably dead code - `windowStart` lies, by construction,
  // after every concluded day, so the condition could never be true. A
  // mutation test confirmed it: removing the lock left every test green. It
  // was therefore removed rather than left standing as a false sense of
  // safety. Whoever changes the window formation here takes FR-11 along with
  // it - the regression tests for it live in test/replan_audit_test.dart.
  final windowStart = dayMarker(lastConcludedDay, 1);
  final window = List.generate(7, (i) => dayMarker(windowStart, i));

  final firstUnprocessedDay =
      markerDay == null ? lastConcludedDay : dayMarker(markerDay, 1);
  final needsDayAdvance =
      dayDistance(firstUnprocessedDay, lastConcludedDay) <= 0;

  final fetchStart = needsDayAdvance ? firstUnprocessedDay : windowStart;
  // New feature (user request): an event the user chose to ignore must play
  // no part in hardFloor derivation - filtered out here, once, so every pure
  // function below (eventsForDay/hardFloor in scheduling_v2.dart) never has
  // to know ignoring exists at all.
  final allEvents = (await fetch(fetchStart, dayMarker(windowStart, 7)))
      .where((event) => !appState.isEventIgnored(event))
      .toList();

  final durationToWakeUp = durationFromTimeOfDay(appState.durationToWakeUp);
  // docs/TODO.md T-52.3: resolved per day rather than once for the whole
  // window - a user override for one weekday must not leak onto any other.
  Duration durationToGetReadyForDay(DateTime day) => durationFromTimeOfDay(
      appState.durationToGetReadyForWeekday(DayOfWeek.values[day.weekday - 1]));

  var possiblyMissedAppointment = false;
  var daysProcessed = 0;
  var daysWithHardFloor = 0;
  final gapCounterBefore = appState.gapDayCounter;

  // FR-9 says "today itself does not count" (today doesn't count yet, since
  // it hasn't concluded) - but from THIS function's own perspective, `ringDay`
  // (the day whose alarm just rang) HAS just concluded, right now: this is
  // the one and only moment its hardFloor status is ever known/processed (see
  // computeWeekPlan's own doc comment: gapDayCounter must already reflect
  // every concluded day up to today BEFORE that call, and "today" there means
  // the day the NEW window starts from, i.e. the day after `ringDay`). So
  // `ringDay` itself is correctly included as the loop's last iteration, not
  // deferred to some later "catch-up" pass that doesn't otherwise exist.
  if (needsDayAdvance) {
    var day = firstUnprocessedDay;
    while (!day.isAfter(lastConcludedDay)) {
      final hf = hardFloor(
        day: day,
        allEvents: allEvents,
        deviceUtcOffset: offset,
        durationToWakeUp: durationToWakeUp,
        durationToGetReady: durationToGetReadyForDay(day),
      );
      appState.gapDayCounter = updateGapDayCounter(
        previousCounter: appState.gapDayCounter,
        dayHadRealHardFloor: hf != null,
      );
      daysProcessed++;
      if (hf != null) daysWithHardFloor++;

      final storedValue =
          instantFromStored(appState.pendingDayValues[isoDate(day)]);
      // docs/TODO.md T-74c: on the very first replan ever there is no history
      // at all, so "an appointment your last alarm may have missed" would be a
      // false positive on a fresh install. Keyed on the progress marker (T-75),
      // i.e. "has any day ever been processed", not on "did a checkpoint run
      // today" - the latter is true even on the first run of the day.
      if (lastProcessedDay != null &&
          hf != null &&
          (storedValue == null || hf.isBefore(storedValue))) {
        // FR-12: a real appointment surfaced too late to have been honored
        // for a day that already rang.
        possiblyMissedAppointment = true;
      }

      day = dayMarker(day, 1);
    }
  }

  // docs/TODO.md T-89: `daysProcessed == 0` on a day whose alarm rang IS the
  // signature of T-75 (a lost day). Previously this finding could only be
  // proven with a hand-written probe test.
  Diag.dayAdvance(
    needsDayAdvance: needsDayAdvance,
    hadProgressMarker: lastProcessedDay != null,
    daysProcessed: daysProcessed,
    daysWithHardFloor: daysWithHardFloor,
    gapCounterBefore: gapCounterBefore,
    gapCounterAfter: appState.gapDayCounter,
    missedAppointmentFlagged: possiblyMissedAppointment,
  );

  final lastEffectiveWakeTime =
      instantFromStored(appState.pendingDayValues[isoDate(lastConcludedDay)]);

  final result = computeWeekPlan(
    window: window,
    lastEffectiveWakeTime: lastEffectiveWakeTime,
    allEvents: allEvents,
    deviceUtcOffset: offset,
    durationToWakeUp: durationToWakeUp,
    durationToGetReadyForDay: durationToGetReadyForDay,
    preferredWakeUpTime: appState.preferredWakeUpTime,
    maxDailyDelta: appState.maxDailyDelta,
    gapDayCounter: appState.gapDayCounter,
    scheduleOnGapDays: appState.scheduleOnGapDays,
  );

  // Merged, not replaced - and the retention below is **load-bearing**, not
  // laziness: the window starts the day after `lastConcludedDay`, so today's
  // own entry (on the recovery path: today has not rung yet) only survives
  // because entries outside the window are kept. FR-18's alarm sync schedules
  // every still-future value in this map, so dropping it would delete today's
  // not-yet-rung alarm on the next checkpoint (e.g. FR-17 after an
  // early-morning reboot) and the user would oversleep. See
  // test/apply_alarms_test.dart's "today's not-yet-rung alarm survives"
  // regression test before changing this.
  //
  // Kept bounded all the same (docs/TODO.md T-82): everything strictly before
  // yesterday is unreachable - `lastEffectiveWakeTime` only ever reads
  // `lastConcludedDay`, and FR-18 only ever schedules future values - so
  // without a cut-off the map just grew by one entry per day forever, in a
  // JSON string that every replan decodes, copies and re-encodes. Yesterday
  // is kept as the margin that makes a recovery checkpoint (whose
  // `lastConcludedDay` *is* yesterday) safe.
  final oldestKeptDay = isoDate(dayMarker(lastConcludedDay, -1));
  bool worthKeeping(String day) => day.compareTo(oldestKeptDay) >= 0;

  // FR-11, second half: "only the value that has actually been triggered is
  // fixed forever" - and "forever" includes the rest of that same day
  // (docs/TODO.md T-106).
  //
  // Only the ring sets `todayAlreadyRang`. For `settingsChanged` and
  // `manualSync` the window therefore starts at TODAY again, even if today
  // rang ten minutes ago - and the merge below would then overwrite the
  // already-triggered value. Consequences: a second alarm the same morning
  // (FR-18 schedules every still-future value), and - worse - the ring day
  // then holds a value that never rang. The next checkpoint reads exactly
  // that as `lastEffectiveWakeTime` (FR-3: "always the entry in
  // `pendingDayValues` for the most recently concluded day"), so the entire
  // following week hangs off a made-up anchor.
  //
  final mergedValues = <String, int?>{
    for (final entry in appState.pendingDayValues.entries)
      if (worthKeeping(entry.key)) entry.key: entry.value,
  };
  final prunedCount = appState.pendingDayValues.length - mergedValues.length;
  for (final day in window) {
    mergedValues[isoDate(day)] = toStored(result.valuesByDay[day]);
  }
  appState.pendingDayValues = mergedValues;
  // FR-21 + T-82: clean up switched-off days with the same bound as the
  // values - a switched-off day in the past interests nobody anymore.
  appState.pruneDisabledDays(oldestKeptDay);
  // docs/TODO.md T-141: the same bound again, for the same reason - nothing
  // else ever shrinks appState.scheduledAlarms, since planAlarmSync's own
  // removal loop deliberately never removes a past-dated alarm (it could be
  // ringing right now).
  appState.setPrunedScheduledAlarms(
    pruneScheduledAlarms(appState.scheduledAlarms, oldestKeptDay: oldestKeptDay),
  );

  // FR-16: the same merge as above (with the same bound), so checkpoint 2
  // also knows, for today's (not-yet-rung) day too, whether its value is
  // instant- or digit-anchored.
  final mergedAnchors = <String, bool>{
    for (final entry in appState.pendingDayInstantAnchored.entries)
      if (worthKeeping(entry.key)) entry.key: entry.value,
  };
  for (final day in window) {
    if (result.valuesByDay[day] == null) {
      mergedAnchors.remove(isoDate(day));
    } else {
      mergedAnchors[isoDate(day)] =
          result.instantAnchoredDays.contains(day);
    }
  }
  appState.pendingDayInstantAnchored = mergedAnchors;

  // `windowDayCount != distinctDayKeys` is the signature of T-74d/T-76: two
  // window days collided onto the same day key.
  // docs/TODO.md T-140: the INPUTS without which the logged plan cannot be
  // recomputed. Always written - durations are not times of day; the
  // preferredWakeUpTime depends on whether it's set and is -1 otherwise.
  // T-52.3: this one value is now only the global default - a per-weekday
  // override (see AppState.durationToGetReadyForWeekday) can make a specific
  // planned day's real input differ from what's logged here. Recording a
  // full per-day breakdown isn't worth the added surface on a PII-free log
  // whose whole point is staying simple to audit.
  Diag.planInputs(
    maxDailyDeltaMinutes: appState.maxDailyDelta.inMinutes,
    wakeUpMinutes: durationToWakeUp.inMinutes,
    getReadyMinutes: durationFromTimeOfDay(appState.durationToGetReady).inMinutes,
    preferredWakeUpMinuteOfDay: appState.preferredWakeUpTime == null
        ? -1
        : appState.preferredWakeUpTime!.hour * 60 + appState.preferredWakeUpTime!.minute,
  );

  Diag.weekPlanComputed(
    todayAlreadyRang: todayAlreadyRang,
    windowDayCount: window.length,
    distinctDayKeys: window.map(isoDate).toSet().length,
    plannedDays: result.valuesByDay.values.whereType<DateTime>().length,
    nullDays: result.valuesByDay.values.where((v) => v == null).length,
    instantAnchoredDays: result.instantAnchoredDays.length,
    overrunFlag: result.overrunNotificationNeeded,
    safetyValveFlag: result.safetyValveTriggered,
    hasPreferredWakeUpTime: appState.preferredWakeUpTime != null,
    maxStep: bucketMinutes(_maxStepMinutes(result.valuesByDay, window)),
    storedEntriesTotal: mergedValues.length,
    storedEntriesPruned: prunedCount,
  );

  // docs/TODO.md T-135: per window day, the planned wake time and the day's
  // earliest appointment, both as a minute of the LOCAL day. Only writes when
  // clock-time logging is explicitly switched on - `Diag.dayPlanned` is a
  // no-op otherwise.
  //
  // Why at all: counts and buckets alone can't reconstruct WHY a day ended up
  // with this wake time. That was exactly what T-132's diagnosis hinged on,
  // and it was only possible via screenshots and hand arithmetic. With these
  // two numbers a week's plan can be recomputed: does the value sit at the
  // appointment (then the two are coupled), on the curve, or at
  // preferredWakeUpTime?
  //
  // Read locally via the same offset that was used to plan - that's the
  // number the user sees in the alarm list (FR-1/T-83's separation of
  // instant and wall clock).
  if (Diag.includeClockTimes) {
    int minuteOfDay(DateTime instant) {
      final local = instant.toUtc().add(offset);
      return local.hour * 60 + local.minute;
    }

    for (final day in window) {
      final planned = result.valuesByDay[day];
      final dayEvents = eventsForDay(day,
          allEvents: allEvents, deviceUtcOffset: offset)
        ..removeWhere((e) => e.isAllDay);
      DateTime? earliest;
      for (final e in dayEvents) {
        if (earliest == null || e.from.toUtc().isBefore(earliest.toUtc())) {
          earliest = e.from;
        }
      }
      Diag.dayPlanned(
        dayOffset: dayDistance(day, today),
        plannedMinuteOfDay: planned == null ? -1 : minuteOfDay(planned),
        earliestEventMinuteOfDay:
            earliest == null ? -1 : minuteOfDay(earliest),
      );
    }
  }

  appState.lastReplanDate = today;
  // Only ever forward (docs/TODO.md T-75): a recovery replan's own
  // `lastConcludedDay` is yesterday, so assigning unconditionally would move
  // the marker *backwards* after a ring checkpoint already concluded today and
  // let today be counted twice.
  if (needsDayAdvance) {
    appState.lastProcessedConcludedDay = lastConcludedDay;
  }

  // docs/TODO.md T-63: turn the computed week into actual alarms. Called here,
  // inside replan() itself, rather than from each checkpoint separately - that
  // way no code path can compute a plan and forget to apply it, which is
  // exactly how the whole engine ended up functionally inert before.
  await applyPlannedAlarms(appState, now: nowFn);

  return ReplanResult(
    overrunNotificationNeeded: result.overrunNotificationNeeded,
    safetyValveTriggered: result.safetyValveTriggered,
    possiblyMissedAppointment: possiblyMissedAppointment,
  );
}

// docs/TODO.md T-87: runAlarmRingCheckpoint(), onAppForegroundCheckpoint() and
// runForegroundCheckpointSafely() used to live here. They have been folded
// into the one entry point runSchedulingCheckpoint() (checkpoint.dart) - the
// same sequence, but formulated exactly once, serialized (T-77) and complete
// (T-80). What told them apart is now CheckpointTrigger there.
//
// This file is thereby reduced back to its actual job: WHAT gets planned
// (FR-8 and FR-16's checkpoint 2), not WHEN and TRIGGERED BY WHAT.

/// FR-16 Checkpoint 2 (docs/scheduling-v2-spec.md): fires at the computed
/// sleep-time notification (Phase 5 step 22's `onNotificationCreatedMethod`),
/// which runs in its own background isolate with **no `AppState`/`Provider`
/// access at all** - unlike [runAlarmRingCheckpoint], this reads/writes
/// `lastCheckedUtcOffset` **directly via `SharedPreferences`**, using the
/// exact same key `AppState.lastCheckedUtcOffset` itself persists to
/// (`lastCheckedUtcOffsetMinutes`), so a later, normal `AppState` load in the
/// main isolate picks up whatever this checkpoint last wrote.
///
/// Per FR-16's own text, Checkpoint 2 "triggers only the time zone
/// comparison, no replanning, no calendar access" - it
/// never calls [replan] and never reads the calendar. What it *does* do on a
/// detected change is FR-16's second half, applied to the still-pending days:
///
/// - **wall-clock-anchored** values (`preferredWakeUpTime`/curve) keep their **local
///   digits** - the alarm-clock convention, "7:00 stays 7:00, now in the new
///   zone" - via [reinterpretForNewOffset];
/// - **instant-anchored** values (taken straight from a real `hardFloor`) keep
///   their **instant**: the appointment does not move, only its local display
///   does (FR-16, "Instant-based values: unchanged").
///
/// Which is which cannot be re-derived here without calendar access, so
/// `computeWeekPlan` records it per day and [replan] persists it next to the
/// values (`pendingDayInstantAnchored`, see `AppState`). Days that already lie
/// in the past are left untouched (FR-11: the value that actually rang is
/// fixed).
///
/// Known limitation, inherent to FR-16's own design: this corrects the stored
/// plan, not the alarms already handed to the platform - FR-16 explicitly
/// defers "the full recomputation" to the next regular planning run,
/// so an alarm that fires between the offset change and the next
/// replan/[applyPlannedAlarms] still uses the pre-change moment.
Future<void> runTimezoneCheckpoint2({
  Duration Function()? readOffset,
  SharedPreferences? prefs,
  DateTime Function()? now,
}) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  final offset = (readOffset ?? () => DateTime.now().timeZoneOffset)();
  final previousMinutes = p.getInt('lastCheckedUtcOffsetMinutes');
  final previousOffset =
      previousMinutes == null ? null : Duration(minutes: previousMinutes);

  if (previousOffset != null && previousOffset != offset) {
    try {
      final rawValues = p.getString('pendingDayValues');
      if (rawValues != null) {
        final values = (jsonDecode(rawValues) as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, value as int?));
        final rawAnchored = p.getString('pendingDayInstantAnchored');
        final anchored = rawAnchored == null
            ? const <String, bool>{}
            : (jsonDecode(rawAnchored) as Map<String, dynamic>)
                .map((key, value) => MapEntry(key, value as bool));
        final nowValue = (now ?? DateTime.now)();

        var changed = false;
        var reinterpreted = 0;
        final updated = Map<String, int?>.from(values);
        values.forEach((day, millis) {
          if (millis == null) return;
          if (anchored[day] == true) return; // instant-anchored: leave alone
          final value = instantFromStored(millis)!;
          if (!value.isAfter(nowValue)) return; // already rung (FR-11)
          updated[day] = toStored(reinterpretForNewOffset(
            value: value,
            oldOffset: previousOffset,
            newOffset: offset,
          ));
          reinterpreted++;
          changed = true;
        });

        if (changed) {
          await p.setString('pendingDayValues', jsonEncode(updated));
        }

        // docs/TODO.md T-62/T-89: if this event shows up in the export, it
        // proves that the silent notification really did trigger the
        // callback - the question T-62 has left open since Phase 5.
        //
        // `Diag.init` is deliberately NOT here, but at the isolate's entry
        // point (`onNotificationCreatedMethod`, lib/utils/notifications.dart):
        // init sets global state (the prefs handle, the isolate id), and this
        // function is also called directly from tests in the main isolate -
        // there it would switch over the main isolate's logger.
        Diag.timezoneCheck(
          offsetChanged: true,
          shape: bucketOffsetChange(previousOffset, offset),
          valuesConsidered: values.length,
          valuesReinterpreted: reinterpreted,
        );
        await Diag.flush();
      }
    } catch (e) {
      // Never let this break the checkpoint's primary job (persisting the
      // offset) - a corrupted/incompatible stored map must not leave the
      // offset stale, or the change would be re-detected forever.
      debugPrint(
          "=====runTimezoneCheckpoint2: reinterpreting pendingDayValues failed: ${e.runtimeType}");
    }
  }

  await p.setInt('lastCheckedUtcOffsetMinutes', offset.inMinutes);
}

/// The largest daily step in the plan, in minutes - input for the
/// `maxStepBucket` bucket field (docs/TODO.md T-89).
///
/// This is exclusively about the **difference** between two planned values,
/// never about an instant itself: a history of wake instants would be a
/// sleep pattern. The nominal day distance is factored out, leaving exactly
/// what FR-6 bounds - the shift in wake time per day. Skipped days (gap days
/// with no value) are counted along the way, otherwise the step would be too
/// large by a multiple of 24 hours.
int _maxStepMinutes(
    Map<DateTime, DateTime?> valuesByDay, List<DateTime> window) {
  const minutesPerDay = 24 * 60;
  var worst = 0;
  DateTime? previousValue;
  DateTime? previousDay;

  for (final day in window) {
    final value = valuesByDay[day];
    if (value == null) continue;
    if (previousValue != null && previousDay != null) {
      final spannedDays = dayDistance(day, previousDay);
      final step = value.difference(previousValue).inMinutes -
          spannedDays * minutesPerDay;
      if (step.abs() > worst.abs()) worst = step;
    }
    previousValue = value;
    previousDay = day;
  }
  return worst;
}
