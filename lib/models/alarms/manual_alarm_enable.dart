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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:wakeywakey/models/alarms/manual_alarm.dart';

// FR-21 (docs/scheduling-v2-spec.md), "Manual alarms" - docs/TODO.md T-03.
//
// A separate, plugin-free and AppState-free file with injectable platform
// calls, the same split as `snooze.dart` and `planAlarmSync`/
// `applyPlannedAlarms`: the decision "which moment does this alarm go back to,
// and what has to happen at the platform" is arithmetic, and it must be
// testable without a device - `Alarm.set` has no channel in a unit test.
//
// Deliberately NOT a test seam inside AppState: a switch that only exists for
// tests but ships in the release binary is the defect docs/TODO.md T-16
// describes.

/// The next moment a manual alarm's bare [time] refers to, honouring
/// [repeatOnDays] (docs/TODO.md T-14).
///
/// This is the resolution `AppState.addAlarm` uses when an alarm is created,
/// `applyManualAlarmEnabled` uses for the FR-21 toggle, and
/// `Handler.onAlarmHandled` uses to re-arm a repeating alarm for its next
/// selected day once the current ring is dismissed - all three go through
/// this one function specifically so none of them can resolve the same
/// alarm to a different day than the others would.
///
/// Searches up to a full week ahead (today plus the next 7 days) for the
/// earliest candidate that is both after [now] and falls on a day
/// [repeatOnDays] marks `true`; a day is looked up by `DateTime.weekday`
/// (`DayOfWeek.values[weekday - 1]`, matching the mapping already used in
/// `screen_alarms.dart`). With every day selected this reduces to the
/// original rule: today at [time] if that is still ahead, otherwise
/// tomorrow.
///
/// If [repeatOnDays] selects no day at all - not reachable from the
/// creation dialog, which pre-selects the current day, but a persisted
/// alarm could still end up here - falling back to the plain
/// today-or-tomorrow rule (ignoring the empty selection) was chosen over
/// never arming the alarm again: a switch that claims to still be armed but
/// silently never rings is exactly the class of bug T-03/FR-21 already
/// fixed once for the enable toggle.
DateTime nextManualOccurrence(
  TimeOfDay time,
  DateTime now,
  Map<DayOfWeek, bool> repeatOnDays,
) {
  final today = DateTime(now.year, now.month, now.day);
  for (var offset = 0; offset <= 7; offset++) {
    final day = today.add(Duration(days: offset));
    final candidate =
        DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!candidate.isAfter(now)) continue;
    final dayOfWeek = DayOfWeek.values[candidate.weekday - 1];
    if (repeatOnDays[dayOfWeek] ?? false) return candidate;
  }
  // No day selected at all: the old, day-agnostic behaviour.
  final todayAtTime =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return todayAtTime.isAfter(now)
      ? todayAtTime
      : todayAtTime.add(const Duration(days: 1));
}

/// Makes the alarm-list toggle of a [ManualAlarm] real (FR-21).
///
/// Returns `true` when the platform accepted the change. On `false` the flag
/// on [alarm] is left **untouched**, and that is the point: if cancelling
/// fails, the alarm will ring, and a switch claiming otherwise would be the
/// same broken promise T-03 was - only better hidden. The caller shows the
/// unchanged state, so the user sees that it did not take.
///
/// The platform call comes first, the flag second, for the same reason
/// `snoozeRingingAlarm` arms before it stops: the recorded state must never
/// describe something the device is not actually doing.
Future<bool> applyManualAlarmEnabled({
  required ManualAlarm alarm,
  required bool enabled,
  required DateTime now,
  required Future<void> Function(ManualAlarm alarm, DateTime at) armAlarm,
  required Future<void> Function(int id) stopAlarm,
}) async {
  try {
    if (enabled) {
      await armAlarm(
          alarm, nextManualOccurrence(alarm.time, now, alarm.repeatOnDays));
    } else {
      await stopAlarm(alarm.id);
    }
  } catch (e) {
    debugPrint(
        "=====applyManualAlarmEnabled: platform call failed: ${e.runtimeType}");
    return false;
  }

  alarm.enabled = enabled;
  return true;
}
