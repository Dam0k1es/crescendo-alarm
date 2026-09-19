// Copyright (C) 2026 Dam0k1es
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

// docs/TODO.md T-63: the missing bridge between scheduling-v2's computed week
// (AppState.pendingDayValues, written by replan()) and the alarms the app
// actually rings. Without this, replan() was functionally inert - every alarm
// still came from the old Scheduler's own, unrelated algorithm.
//
// Split deliberately: planAlarmSync() is pure (no AppState, no plugin, fully
// unit-testable), applyPlannedAlarms() is the thin AppState-facing applier.

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/utils.dart';

/// The difference between the alarms that currently exist and the ones
/// scheduling-v2's plan calls for.
class AlarmSyncPlan {
  const AlarmSyncPlan({required this.toRemove, required this.toAdd});

  /// Existing `ScheduledAlarm`s that no longer correspond to a planned value
  /// (a revised day, a day that became a gap day/safety-valve `null`, or a
  /// stale alarm that already lies in the past).
  final List<ScheduledAlarm> toRemove;

  /// Planned wake times that have no matching alarm yet.
  final List<DateTime> toAdd;
}

/// Truncates to minute precision **in one common frame** - `AppState._setAlarm`
/// hands the plugin a minute-precise local time, so anything finer would
/// produce spurious "different alarm" mismatches on every replan.
///
/// The `.toUtc()` matters (docs/TODO.md T-61): the values being compared come
/// from two different frames - planned values are UTC-tagged instants, while
/// `AlarmSettings.dateTime` from `Alarm.getAlarms()` is a local wall-clock
/// time. Comparing their raw digits would treat a correctly-scheduled alarm as
/// "missing from the platform" on every device outside UTC+0, re-setting it on
/// every replan.
DateTime _toMinute(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
}

/// Pure: computes what has to change so the set of `ScheduledAlarm`s matches
/// [pendingDayValues] exactly.
///
/// Only values strictly after [now] are ever scheduled: a day whose value
/// already lies in the past has, by definition, either already rung (FR-11:
/// "only the value that has actually been triggered is fixed forever" -
/// re-setting it would be pointless) or been missed entirely, and the alarm plugin rejects
/// past times anyway. A `null` value (FR-9's safety valve, or FR-10's cold
/// start without a `preferredWakeUpTime`) means "no alarm planned for that day", so any
/// existing alarm for it gets removed rather than kept.
///
/// **Past-dated existing alarms are deliberately never removed.** This sync
/// runs (via `replan()`) from `Handler.handleAlarm()`'s ring checkpoint, i.e.
/// while an alarm is *actively ringing* - and that alarm's own time has just
/// moved into the past. Treating it as "stale, no longer planned" and calling
/// `AppState.removeAlarm` on it would `Alarm.stop()` the ringing alarm
/// mid-ring and silently defeat the guaranteed-wake-up feature. Cleaning up
/// genuinely stale past alarms is `handleAlarm`'s own job (see `isAlarmStale`),
/// not this function's.
/// [platformAlarmIds], when given, are the **ids** the platform actually still
/// has scheduled (`Alarm.getAlarms()`). `AppState`'s own list can diverge from
/// it - an alarm cancelled natively (e.g. the QR dismiss path before T-74e, or
/// an OS-level clear) stays in `AppState` and would make this sync a no-op,
/// leaving the user with no alarm. A planned day whose alarm is missing from
/// the platform is therefore re-created (and its stale `AppState` entry removed
/// first). `null` means "platform state unknown" (e.g. the plugin is
/// unavailable), in which case only `AppState` is used.
///
/// Ids, not times (docs/TODO.md T-88): matching by time treated an unrelated
/// platform alarm on the same minute - a `ManualAlarm`, which `Alarm.getAlarms()`
/// returns too - as proof that *this* `ScheduledAlarm` was still scheduled. Ids
/// are also frame-free, so the whole T-61 hazard of comparing a UTC-tagged
/// instant against the plugin's local wall clock disappears from this boundary.
///
/// [tone]/[volume]/[vibrate]/[gentleWake]/[gentleWakeDuration] are the
/// properties the plan calls for (`AppState`'s current settings). When
/// given, an existing alarm whose own properties differ is replaced, not
/// kept (docs/TODO.md T-84, and T-50 for [vibrate]): the comparison used to
/// be time-only, so a changed tone or volume only ever took effect on days
/// that happened to be replanned anyway. Omitting them keeps the time-only
/// comparison, so no caller that doesn't know the settings can accidentally
/// re-set every alarm.
AlarmSyncPlan planAlarmSync({
  required Map<String, int?> pendingDayValues,
  required List<ScheduledAlarm> existingScheduledAlarms,
  required DateTime now,
  Set<int>? platformAlarmIds,
  /// FR-21: days for which the user has explicitly switched off the alarm.
  /// They are treated as if nothing were planned for them - but the value
  /// itself stays in place (switched off is not deleted), so it applies
  /// again immediately when switched back on, and the smoothing can keep
  /// using it as an anchor.
  Set<String>? disabledDays,
  String? tone,
  double? volume,
  bool? vibrate,
  bool? gentleWake,
  Duration? gentleWakeDuration,
}) {
  final nowMinute = _toMinute(now);

  final desired = <DateTime>[];
  for (final entry in pendingDayValues.entries) {
    // FR-21: the user has said "don't wake me" for this day. This must
    // apply HERE, not only at arming time: `applyPlannedAlarms` rebuilds the
    // alarm set from this list on every replan, so a bare `Alarm.stop()` at
    // the surface wouldn't last until the next checkpoint.
    if (disabledDays != null && disabledDays.contains(entry.key)) continue;
    final millis = entry.value;
    // localFromStored, not instantFromStored (docs/TODO.md T-83): these
    // values land in ScheduledAlarm.time, and its title (formatDateTime) as
    // well as the alarm list in the UI read the digits as wall-clock time.
    final value = localFromStored(millis);
    if (value == null) continue;
    if (!_toMinute(value).isAfter(nowMinute)) continue;
    desired.add(value);
  }

  final desiredMinutes = desired.map(_toMinute).toSet();

  bool onPlatform(ScheduledAlarm alarm) =>
      platformAlarmIds == null || platformAlarmIds.contains(alarm.id);

  bool propertiesMatch(ScheduledAlarm alarm) =>
      (tone == null || alarm.tone == tone) &&
      (volume == null || alarm.volume == volume) &&
      (vibrate == null || alarm.vibrate == vibrate) &&
      (gentleWake == null || alarm.gentlewake == gentleWake) &&
      // docs/TODO.md T-96: only relevant while Gentle Wake is on at all -
      // with Gentle Wake off, `_setAlarm` doesn't use the ramp at all, so a
      // difference in it would be no reason to re-arm an alarm.
      (gentleWakeDuration == null ||
          alarm.gentlewake == false ||
          alarm.gentleWakeDuration == gentleWakeDuration);

  /// An existing alarm is only "good enough to keep" if it is planned, still
  /// present on the platform, and carries the properties the plan calls for.
  bool matchesPlan(ScheduledAlarm alarm) =>
      desiredMinutes.contains(_toMinute(alarm.time)) &&
      onPlatform(alarm) &&
      propertiesMatch(alarm);

  // Every planned value can be claimed by at most ONE alarm
  // (docs/TODO.md T-116).
  //
  // Previously this was mere set membership: if two alarms sat on the same
  // minute, *both* counted as worth keeping, neither as surplus - and
  // because that also left `toAdd` empty, the state was a stable fixed
  // point: every further replan confirmed the duplicate, and the user was
  // woken twice, permanently. FR-18's lead sentence, though, demands a
  // statement about the SET ("reconciled so that it matches **exactly** the
  // planned values"), and this function's own contract says "matches
  // [pendingDayValues] **exactly**".
  //
  // Order-dependent, and deliberately so: the first matching alarm claims
  // the value, every further one is dropped. Removal is by alarm id
  // (`applyPlannedAlarms` -> `appState.removeAlarm`), so it matters that the
  // survivor specifically is NOT in `toRemove` - otherwise removal would
  // stop it on the platform too.
  final claimedMinutes = <DateTime>{};
  final toRemove = <ScheduledAlarm>[];
  for (final alarm in existingScheduledAlarms) {
    final minute = _toMinute(alarm.time);
    // FR-18, safety-critical: an alarm in the past is NEVER removed - it
    // could be ringing right now, and `Alarm.stop()` would defeat the
    // guaranteed wake-up. It therefore also never claims a value: `desired`
    // only ever contains instants after now anyway.
    if (!minute.isAfter(nowMinute)) continue;
    if (matchesPlan(alarm) && claimedMinutes.add(minute)) continue;
    toRemove.add(alarm);
  }

  final toAdd = desired
      .where((value) => !claimedMinutes.contains(_toMinute(value)))
      .toList();

  return AlarmSyncPlan(toRemove: toRemove, toAdd: toAdd);
}

/// docs/TODO.md T-141: `planAlarmSync`'s removal loop above deliberately
/// never removes a past-dated alarm - it could be ringing at this very
/// moment, and treating it as stale would let a replan call `Alarm.stop()`
/// mid-ring and defeat the guaranteed wake-up. Nothing else ever shrinks
/// `AppState.scheduledAlarms`, so it grows by one entry per planned day
/// forever (seen live: seven alarms in the Scheduled tab, six of them for
/// days already over). This is that separate, bounded cleanup - kept apart
/// from `planAlarmSync` on purpose, so its own safety-critical "never touch
/// anything that could be ringing" rule stays the only thing governing
/// removal there.
///
/// [oldestKeptDay] is an ISO date (`isoDate`) - the same bound `replan()`
/// already uses for `pendingDayValues`/`disabledDays` (docs/TODO.md T-82,
/// "yesterday", so a recovery checkpoint whose `lastConcludedDay` *is*
/// yesterday still has it to read). An alarm is kept if its own day (by
/// `ScheduledAlarm.time`'s wall-clock digits - the same frame its FR-21
/// toggle already keys `disabledDays` by) is on or after it.
///
/// Deliberately day-based, not "still in the future": today's alarm is
/// always kept even though `time` may already be minutes in the past by the
/// moment this runs - it could still be actively ringing. Cleaning up a
/// genuinely stale one (already rung, in the past) is `Handler.handleAlarm`'s
/// job (`isAlarmStale`), not this function's.
List<ScheduledAlarm> pruneScheduledAlarms(
  List<ScheduledAlarm> alarms, {
  required String oldestKeptDay,
}) {
  return alarms
      .where((alarm) => isoDate(alarm.time).compareTo(oldestKeptDay) >= 0)
      .toList();
}

/// Applies [planAlarmSync]'s result to [appState] - the step that actually
/// makes scheduling-v2 ring alarms.
///
/// FR-15 (`ManualAlarm`-Isolation) holds structurally: this only ever reads
/// `appState.scheduledAlarms` and only ever creates `ScheduledAlarm`s -
/// `manualAlarms` is never read or written. Each add/remove is individually
/// guarded so one failing plugin call (`Alarm.set`/`Alarm.stop`) can't abort
/// the rest of the sync.
Future<void> applyPlannedAlarms(
  AppState appState, {
  DateTime Function()? now,
}) async {
  final nowFn = now ?? DateTime.now;

  // Reconcile against what the platform really has, not just what AppState
  // believes (docs/TODO.md T-74e). Unavailable plugin -> fall back to
  // AppState-only.
  Set<int>? platformIds;
  Map<int, DateTime> platformTimes = const <int, DateTime>{};
  try {
    final platformAlarms = await Alarm.getAlarms();
    platformIds = platformAlarms.map((a) => a.id).toSet();
    platformTimes = {for (final a in platformAlarms) a.id: a.dateTime};
  } catch (e) {
    debugPrint("=====applyPlannedAlarms: Alarm.getAlarms() unavailable: ${e.runtimeType}");
  }

  final existing = List<ScheduledAlarm>.from(appState.scheduledAlarms);
  final plan = planAlarmSync(
    pendingDayValues: appState.pendingDayValues,
    existingScheduledAlarms: existing,
    disabledDays: appState.disabledDays,
    now: nowFn(),
    platformAlarmIds: platformIds,
    // docs/TODO.md T-84: the alarm properties belong in the reconciliation,
    // otherwise a changed setting only affects days that get freshly planned anyway.
    tone: appState.selectedTone,
    volume: appState.selectedVolume,
    vibrate: appState.vibrationEnabled,
    gentleWake: appState.gentleWakeUpEnabled,
    gentleWakeDuration: appState.gentleWakeUpDuration,
  );

  var removeFailures = 0;
  for (final alarm in plan.toRemove) {
    try {
      await appState.removeAlarm(alarm);
    } catch (e) {
      removeFailures++;
      Diag.failure(
        at: DiagEvent.alarmSync,
        exceptionType: e.runtimeType,
        kind: ErrorKind.plugin,
      );
      debugPrint("=====applyPlannedAlarms: removeAlarm failed: ${e.runtimeType}");
    }
  }

  var addFailures = 0;
  for (final value in plan.toAdd) {
    try {
      await appState.addAlarm(ScheduledAlarm(
        time: value,
        enabled: true,
        gentlewake: appState.gentleWakeUpEnabled,
        gentleWakeDuration: appState.gentleWakeUpDuration,
        tone: appState.selectedTone,
        volume: appState.selectedVolume,
        vibrate: appState.vibrationEnabled,
        id: getRandom(),
      ));
    } catch (e) {
      addFailures++;
      Diag.failure(
        at: DiagEvent.alarmSync,
        exceptionType: e.runtimeType,
        kind: ErrorKind.plugin,
      );
      debugPrint("=====applyPlannedAlarms: addAlarm failed for $value: ${e.runtimeType}");
    }
  }

  // docs/TODO.md T-89: T-64 would have been immediately visible here as a
  // large `toRemove` with `toAdd == 0`, T-74e as `platformStateUnknown` or
  // as a divergence between `existingAlarms` and what the platform knows.
  Diag.alarmSync(
    desiredAlarms: plan.toAdd.length + existing.length - plan.toRemove.length,
    existingAlarms: existing.length,
    platformStateUnknown: platformIds == null,
    toRemove: plan.toRemove.length,
    toAdd: plan.toAdd.length,
    removeFailures: removeFailures,
    addFailures: addFailures,
    plannedVsPlatform: bucketMinutes(_worstPlatformDriftMinutes(
        appState.scheduledAlarms, platformTimes)),
  );

  debugPrint(
      "=====applyPlannedAlarms: removed ${plan.toRemove.length}, added ${plan.toAdd.length}");
}

/// The largest deviation between a `ScheduledAlarm` in `AppState` and what
/// the platform knows for the same id - in minutes, input for the
/// `plannedVsPlatformBucket` bucket field (docs/TODO.md T-89).
///
/// This is exactly the frame boundary T-61 sat on: a planned value is a
/// UTC-tagged instant, `AlarmSettings.dateTime` a local wall-clock time. A
/// deviation of exactly one hour, or exactly one device offset, is that
/// bug's signature - and it's visible in the log without any instant itself
/// ever being recorded.
int _worstPlatformDriftMinutes(
    List<ScheduledAlarm> alarms, Map<int, DateTime> platformTimes) {
  var worst = 0;
  for (final alarm in alarms) {
    final onPlatform = platformTimes[alarm.id];
    if (onPlatform == null) continue;
    final drift = onPlatform.difference(alarmPlatformTime(alarm.time)).inMinutes;
    if (drift.abs() > worst.abs()) worst = drift;
  }
  return worst;
}
