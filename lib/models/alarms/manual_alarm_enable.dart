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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

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
///
/// docs/TODO.md T-181: the day-search below walks via [dayMarker] (over
/// calendar date FIELDS), not `today.add(Duration(days: offset))` - across a
/// daylight-saving transition, adding a fixed real-time Duration to a local
/// midnight lands short of the intended calendar day (this project's own
/// `day_marker.dart` doc comment explains why, having already fixed the same
/// bug class once for the scheduling engine, T-74d/T-76). This function
/// reintroduced it independently: found via a CI-only failure on the
/// `Australia/Lord_Howe` timezone leg, where the 7-day search window can
/// straddle a transition and silently corrupt every subsequent candidate's
/// calendar day, making the loop miss its target and fall through to the
/// wrong weekday entirely.
///
/// docs/TODO.md T-202 (TZ-1): each candidate day's reading is turned into an
/// instant by TZ-1's resolution (`lib/utils/wall_clock.dart`), not by
/// `DateTime(...)`. On a
/// daylight-saving change day that is the difference between the app's rule
/// and Dart's default: a reading in the repeated hour rings at its LATER
/// occurrence (Dart: the first), a reading in the skipped hour at the first
/// valid instant after the gap, 03:00 in Europe/Berlin (Dart: shifted by
/// the gap, 03:30). A skipped reading therefore rings at the change itself,
/// never at the next day's reading.
///
/// docs/TODO.md T-206 (TZ-2a, maintainer: "Manual alarms: yes"): the
/// resolution is [resolvePlannedClockTime] - R_plan, the same one the
/// scheduling engine uses - not plain R. They differ only where the gap ends
/// at midnight (America/Nuuk, 28 Mar 2026: 23:00 -> 00:00): R's instant would
/// carry the NEXT date, so a manual 23:30 rings at the minute before the gap
/// instead, 22:59 on its own date, like a scheduled 23:30 that night.
DateTime nextManualOccurrence(
  TimeOfDay time,
  DateTime now,
  Map<DayOfWeek, bool> repeatOnDays,
) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime onDay(DateTime day) => resolvePlannedClockTime(
          DateTime.utc(day.year, day.month, day.day, time.hour, time.minute),
          deviceOffsetAt)
      .toLocal();
  for (var offset = 0; offset <= 7; offset++) {
    final day = dayMarker(today, offset);
    final candidate = onDay(day);
    if (!candidate.isAfter(now)) continue;
    // The candidate DAY's weekday, not the resolved instant's: the same in
    // every real case, but the day is what `repeatOnDays` selects.
    final dayOfWeek = DayOfWeek.values[day.weekday - 1];
    if (repeatOnDays[dayOfWeek] ?? false) return candidate;
  }
  // No day selected at all: the old, day-agnostic behaviour.
  final todayAtTime = onDay(today);
  if (todayAtTime.isAfter(now)) return todayAtTime;
  return onDay(dayMarker(today, 1));
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
