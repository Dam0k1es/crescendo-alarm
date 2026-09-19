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

import 'package:flutter/foundation.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/utils.dart';

// FR-20 (docs/scheduling-v2-spec.md): snooze postpones a wake call, but never
// disables it.
//
// Deliberately its own file, free of plugins and AppState, with pure
// functions: the decision "may it still be postponed?" is a calculation, not
// UI, and needs no platform access, and it's needed in three places (the
// default ring screen, the QR screen, and the tests). Same split as
// `planAlarmSync`/`applyPlannedAlarms`.

/// May the wake call be postponed once more?
///
/// The budget is [wakeUpBudget] - `durationToWakeUp`, the time to become
/// properly awake - and that's no coincidence: FR-2 sets the wake instant to
/// `earliest appointment − durationToWakeUp − durationToGetReady`. Snooze may
/// only consume the first duration, never the one for getting ready. From
/// this follows the load-bearing guarantee, without needing to be checked
/// separately: **someone who only snoozes still gets out the door on time.**
///
/// Measured from [originalRing], the *original* wake instant - not from the
/// last press. Letting the alarm ring for a long time before pressing snooze
/// therefore saves nothing; the budget is the total postponement, not the
/// number of presses.
///
/// The boundary is inclusive: a postponement that lands exactly on
/// `originalRing + wakeUpBudget` is still allowed.
bool canSnooze({
  required DateTime now,
  required DateTime originalRing,
  required Duration snoozeTime,
  required Duration wakeUpBudget,
  required bool snoozeEnabled,
}) {
  if (!snoozeEnabled) return false;
  final latestAllowed = originalRing.add(wakeUpBudget);
  return !snoozedRingTime(now: now, snoozeTime: snoozeTime)
      .isAfter(latestAllowed);
}

/// When the postponed wake call rings.
///
/// From **now**, not from the original call: after a press, the user expects
/// exactly [snoozeTime] of quiet, regardless of how long they let the alarm
/// run before that.
DateTime snoozedRingTime({
  required DateTime now,
  required Duration snoozeTime,
}) =>
    now.add(snoozeTime);

/// Postpones the currently ringing wake call by [AppState.snoozeTime].
///
/// Returns `true` if it was actually postponed. `false` means: it wasn't
/// allowed (budget exhausted or snooze off), or the platform didn't accept
/// the new call - in both cases the alarm keeps ringing, or stays unchanged
/// either way. An alarm is **never** switched off here without a new one
/// standing in its place.
///
/// Two things that are deliberately this way (FR-20):
///
/// 1. The postponed call is a **plain platform alarm with a new id**, which
///    `AppState` does not track as a `ScheduledAlarm`. Otherwise FR-18 would
///    remove it at the next reconciliation: it lies in the future and has no
///    planned counterpart. A platform entry with no counterpart, by
///    contrast, is left untouched (docs/TODO.md T-127).
/// 2. The **origin call is carried along** to the new id. Otherwise the
///    budget would restart from zero on every snooze, and "at most
///    `durationToWakeUp`" would have no effect.
Future<bool> snoozeRingingAlarm(
  AppState appState, {
  required int alarmId,
  required DateTime ringTime,
  DateTime Function()? now,
  required Future<void> Function(int id, DateTime at) setAlarm,
  required Future<void> Function(int id) stopAlarm,
  int Function()? newId,
}) async {
  final nowFn = now ?? DateTime.now;
  final origin = appState.snoozeOriginFor(alarmId) ?? ringTime;
  final at = nowFn();

  if (!canSnooze(
    now: at,
    originalRing: origin,
    snoozeTime: appState.snoozeTime,
    wakeUpBudget: durationFromTimeOfDay(appState.durationToWakeUp),
    snoozeEnabled: appState.snoozeEnabled,
  )) {
    return false;
  }

  final next = snoozedRingTime(now: at, snoozeTime: appState.snoozeTime);
  final id = (newId ?? getRandom)();

  // Arm the new call first, then end the old one: if arming fails, the old
  // one keeps ringing - that's the safe outcome. The other way around, a
  // failure would have left the user without any alarm at all.
  try {
    await setAlarm(id, next);
  } catch (e) {
    debugPrint("=====snoozeRingingAlarm: setAlarm failed: ${e.runtimeType}");
    return false;
  }

  appState.rememberSnoozeOrigin(id, origin);
  appState.forgetSnoozeOrigin(alarmId);

  try {
    await stopAlarm(alarmId);
  } catch (e) {
    // The new call is already armed - that's the state that actually matters.
    debugPrint("=====snoozeRingingAlarm: stopAlarm failed: ${e.runtimeType}");
  }
  return true;
}
