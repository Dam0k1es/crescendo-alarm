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
import 'package:wakeywakey/models/scheduling/stored_values.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/utils.dart';

/// The difference between the alarms that currently exist and the ones
/// scheduling-v2's plan calls for.
class AlarmSyncPlan {
  const AlarmSyncPlan({required this.toRemove, required this.toAdd});

  /// Existing `ScheduledAlarm`s that no longer correspond to a planned value
  /// (a revised day, a day that became a Lückentag/safety-valve `null`, or a
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
/// "erst der tatsächlich ausgelöste Wert ist für immer fix" - re-setting it
/// would be pointless) or been missed entirely, and the alarm plugin rejects
/// past times anyway. A `null` value (FR-9's safety valve, or FR-10's cold
/// start without a `wunschzeit`) means "no alarm planned for that day", so any
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
/// [tone]/[volume]/[gentleWake]/[gentleWakeDuration] are the properties the plan calls for
/// (`AppState`'s current settings). When given, an existing alarm whose own
/// properties differ is replaced, not kept (docs/TODO.md T-84): the comparison
/// used to be time-only, so a changed tone or volume only ever took effect on
/// days that happened to be replanned anyway. Omitting them keeps the
/// time-only comparison, so no caller that doesn't know the settings can
/// accidentally re-set every alarm.
AlarmSyncPlan planAlarmSync({
  required Map<String, int?> pendingDayValues,
  required List<ScheduledAlarm> existingScheduledAlarms,
  required DateTime now,
  Set<int>? platformAlarmIds,
  String? tone,
  double? volume,
  bool? gentleWake,
  Duration? gentleWakeDuration,
}) {
  final nowMinute = _toMinute(now);

  final desired = <DateTime>[];
  for (final millis in pendingDayValues.values) {
    // localFromStored, nicht instantFromStored (docs/TODO.md T-83): diese
    // Werte landen in ScheduledAlarm.time, und dessen Titel (formatDateTime)
    // sowie die Alarmliste in der UI lesen die Ziffern als Wanduhrzeit.
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
      (gentleWake == null || alarm.gentlewake == gentleWake) &&
      // docs/TODO.md T-96: nur relevant, solange Gentle Wake ueberhaupt an
      // ist - bei ausgeschaltetem Gentle Wake benutzt `_setAlarm` die Rampe
      // gar nicht, ein Unterschied darin waere also kein Grund, einen Alarm
      // neu zu setzen.
      (gentleWakeDuration == null ||
          alarm.gentlewake == false ||
          alarm.gentleWakeDuration == gentleWakeDuration);

  /// An existing alarm is only "good enough to keep" if it is planned, still
  /// present on the platform, and carries the properties the plan calls for.
  bool keepable(ScheduledAlarm alarm) =>
      desiredMinutes.contains(_toMinute(alarm.time)) &&
      onPlatform(alarm) &&
      propertiesMatch(alarm);

  final toRemove = existingScheduledAlarms.where((alarm) {
    if (!_toMinute(alarm.time).isAfter(nowMinute)) return false;
    return !keepable(alarm);
  }).toList();

  final keptMinutes =
      existingScheduledAlarms.where(keepable).map((a) => _toMinute(a.time)).toSet();

  final toAdd =
      desired.where((value) => !keptMinutes.contains(_toMinute(value))).toList();

  return AlarmSyncPlan(toRemove: toRemove, toAdd: toAdd);
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
    now: nowFn(),
    platformAlarmIds: platformIds,
    // docs/TODO.md T-84: die Alarm-Eigenschaften gehören zum Abgleich, sonst
    // wirkt eine geänderte Einstellung nur auf ohnehin neu geplante Tage.
    tone: appState.selectedTone,
    volume: appState.selectedVolume,
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

  // docs/TODO.md T-89: T-64 waere hier als grosses `toRemove` bei `toAdd == 0`
  // sofort sichtbar gewesen, T-74e als `platformStateUnknown` bzw. als
  // Divergenz zwischen `existingAlarms` und dem, was die Plattform kennt.
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

/// Die groesste Abweichung zwischen einem `ScheduledAlarm` in `AppState` und
/// dem, was die Plattform fuer dieselbe ID kennt - in Minuten, Eingabe fuer das
/// Bucket-Feld `plannedVsPlatformBucket` (docs/TODO.md T-89).
///
/// Das ist genau die Frame-Grenze, an der T-61 sass: ein Planwert ist ein
/// UTC-getaggter Instant, `AlarmSettings.dateTime` eine lokale Wanduhrzeit.
/// Eine Abweichung von exakt einer Stunde oder exakt einem Geraeteversatz ist
/// die Signatur dieses Fehlers - und sie ist im Log sichtbar, ohne dass
/// irgendein Zeitpunkt selbst aufgezeichnet wird.
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
