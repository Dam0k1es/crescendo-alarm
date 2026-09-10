// docs/TODO.md T-66: the Phase-6-proof replacement for
// `Scheduler.nextAlarmTime()`. Pure (no AppState, no plugin), so it survives
// removing the old Scheduler and is directly unit-testable.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';

/// The next wake-up moment the user can actually expect, considering **both**
/// sources: scheduling-v2's planned days ([pendingDayValues], as persisted by
/// `replan()`) and the user's [manualAlarms].
///
/// Reading `manualAlarms` here is deliberate and not an FR-15 violation:
/// FR-15 forbids the *scheduling* logic from letting manual alarms influence
/// the computed `ScheduledAlarm` chain. This function feeds the bedtime
/// reminder (FR-16 Checkpoint 2's hook, `scheduleSleepReminder`), and a user
/// who only ever sets manual alarms must still get a sensible bedtime - the
/// old `Scheduler.nextAlarmTime()` considered both for exactly that reason.
///
/// A manual alarm carries only a [TimeOfDay], so it resolves to its next
/// occurrence: today at that time if that is still after [now], otherwise
/// tomorrow - matching `AppState._getAlarmTime`, i.e. the time the alarm would
/// actually be set to. `repeatOnDays` is deliberately not consulted, because
/// nothing in the app evaluates it when setting alarms either (it is stored
/// and editable, but never acted on), and `enabled` is not consulted either
/// (the per-alarm switch is a known no-op app-wide, `docs/TODO.md` T-03) -
/// this function mirrors actual current alarm behavior rather than inventing
/// its own.
///
/// Returns `null` when neither source yields a future wake-up time; callers
/// decide what to do with that (see `scheduleSleepReminder`'s fallback).
DateTime? nextWakeUpTime({
  required Map<String, int?> pendingDayValues,
  required List<ManualAlarm> manualAlarms,
  required DateTime now,
}) {
  DateTime? earliest;

  void consider(DateTime candidate) {
    if (!candidate.isAfter(now)) return;
    if (earliest == null || candidate.isBefore(earliest!)) {
      earliest = candidate;
    }
  }

  for (final millis in pendingDayValues.values) {
    // localFromStored (docs/TODO.md T-83): dieselbe Lesart wie auf der
    // Manual-Alarm-Seite unten, die aus `now`s lokalen Feldern baut - beide
    // Kandidaten müssen im selben Frame verglichen werden.
    final planned = localFromStored(millis);
    if (planned == null) continue;
    consider(planned);
  }

  for (final alarm in manualAlarms) {
    // `MyAlarm.time` is declared `dynamic` (a `DateTime` for `ScheduledAlarm`,
    // a `TimeOfDay` for `ManualAlarm`) - hence the cast.
    final time = alarm.time as TimeOfDay;
    var occurrence =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!occurrence.isAfter(now)) {
      occurrence = occurrence.add(const Duration(days: 1));
    }
    consider(occurrence);
  }

  return earliest;
}
