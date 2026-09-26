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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/utils/do_not_disturb_channel.dart';

// docs/TODO.md T-184 (maintainer request): "in der Schlafenszeit (sleep
// goal) vor dem Wecker (ohne reminder Zeit) benachrichtigungen deaktivieren
// und ab dem Wecker (nach snooze time, nur finaler Alarm) wieder auf den
// Zustand vorher (vibration, ton, etc) setzen" - silence notifications from
// bedtime (wakeTime - sleepGoal, deliberately NOT also subtracting
// reminderDuration - that is the earlier, separate reminder notification's
// own instant) until the alarm's FINAL ring (the one no further snooze could
// still postpone), then put the device back exactly how it was.
//
// Deliberately its own file, free of AppState/scheduling/the platform
// channel itself - the same split as snooze.dart/manual_alarm_enable.dart:
// "what state do we end up in" is a calculation, testable without a device.
//
// Persisted via `shared_preferences`, not held only in memory: activation and
// restoration happen from two different, independent triggers (a scheduled
// background-isolate notification, and whichever ring turns out to be the
// final one - possibly after a process death in between), so only something
// that survives a restart can carry "what to restore to" between them.

/// The `SharedPreferences` key the device's interruption filter from just
/// before activation is stored under - present if and only if Do Not Disturb
/// is currently active because of this feature.
const String doNotDisturbPreviousFilterKey = 'doNotDisturbPreviousFilter';

/// The `SharedPreferences` key the activation instant is stored under
/// (millisecondsSinceEpoch) - purely for [restoreStaleDoNotDisturb]'s safety
/// net, unrelated to anything [restoreDoNotDisturb] itself needs.
const String doNotDisturbActivatedAtKey = 'doNotDisturbActivatedAt';

/// The `SharedPreferences` key the WAKE-UP instant Do Not Disturb was most
/// recently scheduled around is stored under (millisecondsSinceEpoch) -
/// written by `scheduleDoNotDisturbActivation` (`do_not_disturb_schedule.dart`)
/// every time it (re-)computes the bedtime, read by [isTargetWakeUpRing].
const String doNotDisturbTargetWakeUpKey = 'doNotDisturbTargetWakeUp';

/// docs/TODO.md T-184 (independent review finding, 2026-09-25): a ring being
/// "final" (no further snooze possible) is not, by itself, enough to restore
/// Do Not Disturb - Do Not Disturb is scheduled around ONE specific wake-up
/// instant (whichever `nextWakeUpTime` considered earliest at the moment
/// `scheduleDoNotDisturbActivation` last ran), not around "whatever alarm
/// happens to ring and become final first". Without this check, an unrelated
/// alarm (a manual reminder with Snooze switched off, or one that simply
/// exhausts its own small snooze budget before the real wake-up is even due)
/// would restore Do Not Disturb hours early - silencing nothing for the rest
/// of the night, exactly the failure mode the feature exists to prevent.
///
/// Deliberately compares against a PERSISTED target rather than
/// re-deriving `nextWakeUpTime` fresh at ring time: recomputing it right
/// before any alarm rings would trivially return that very alarm's own time
/// (it is, by definition, the soonest thing not yet passed), which would
/// make the check a no-op - it has to ask "is this the wake-up Do Not
/// Disturb was ACTUALLY scheduled around", not "is this the soonest thing
/// happening right now".
///
/// A `null` stored value (Do Not Disturb was never scheduled, is disabled, or
/// this ran before the target was first persisted) is treated as a match -
/// nothing to compare against, so this ring must be the one. A small
/// tolerance (not exact equality) absorbs any independent minute-truncation
/// between the two DateTimes' own derivations (`alarmPlatformTime`, the
/// notification scheduler) without weakening the check in practice - the
/// unrelated-alarm scenario above differs by hours, not minutes.
bool isTargetWakeUpRing(SharedPreferences prefs, DateTime candidateRing) {
  final targetMillis = prefs.getInt(doNotDisturbTargetWakeUpKey);
  if (targetMillis == null) return true;
  final target = DateTime.fromMillisecondsSinceEpoch(targetMillis);
  return candidateRing.difference(target).abs() <=
      const Duration(minutes: 2);
}

/// How long Do Not Disturb may stay active before the safety net restores it
/// regardless of whether an alarm ever rang - generous enough to cover any
/// real sleep+wake+workday, deliberately NOT tied to any particular wake
/// time or snooze budget (re-deriving those here would risk getting THIS
/// safety check wrong too, the exact opposite of what a safety net is for).
const Duration maxDoNotDisturbDuration = Duration(hours: 18);

/// Turns Do Not Disturb on (`interruptionFilterAlarms` - alarms only, never
/// [interruptionFilterNone], which would silence the alarm clock's own
/// alarm too) for bedtime, remembering the current filter first so it can be
/// restored later.
///
/// If a previous state is already remembered, [getCurrentFilter] is not
/// called again and nothing is overwritten - guards against two activations
/// in a row (e.g. a rescheduled notification somehow firing twice) replacing
/// the real "before" state with one this feature itself already produced.
///
/// Returns whether the device actually ended up in Do Not Disturb - `false`
/// covers both "the current filter could not even be read" (nothing is
/// touched in that case) and "the platform refused to set it" (most likely:
/// `ACCESS_NOTIFICATION_POLICY` was never granted).
Future<bool> activateDoNotDisturb({
  required SharedPreferences prefs,
  required Future<int?> Function() getCurrentFilter,
  required Future<bool> Function(int filter) setFilter,
  DateTime Function()? now,
}) async {
  if (!prefs.containsKey(doNotDisturbPreviousFilterKey)) {
    final current = await getCurrentFilter();
    // docs/TODO.md T-186 (independent review finding, Philipp): verified
    // against AOSP's NotificationManagerService - every real filter value
    // (all/priority/alarms/none) round-trips through setInterruptionFilter,
    // but interruptionFilterUnknown does not; it throws
    // IllegalArgumentException every time. getCurrentInterruptionFilter is
    // documented to return exactly that value "if unavailable for any
    // reason" (e.g. right after boot). Persisting it here as "the state to
    // restore to" would mean every later restore attempt - including the
    // 18-hour safety net - fails forever, with no way to ever recover: the
    // device stuck silencing everything but its own alarm indefinitely.
    if (current == null || current == interruptionFilterUnknown) return false;
    await prefs.setInt(doNotDisturbPreviousFilterKey, current);
    // Recorded purely for restoreStaleDoNotDisturb's safety net - only set
    // alongside a genuinely NEW previous-state capture, same reasoning as
    // that capture itself not being overwritten by a second activation.
    await prefs.setInt(
        doNotDisturbActivatedAtKey, (now ?? DateTime.now)().millisecondsSinceEpoch);
  }
  return setFilter(interruptionFilterAlarms);
}

/// Restores whatever interruption filter was remembered by
/// [activateDoNotDisturb], and forgets it - a no-op (returns `false`) if
/// nothing is currently remembered, i.e. Do Not Disturb was never activated
/// by this feature in the first place.
///
/// The remembered state is only cleared once [setFilter] actually succeeds -
/// a failed restore leaves it in place, so a later attempt (the next ring,
/// or the safety-net check `runSchedulingCheckpoint` makes on every app
/// open) can still recover the real previous state rather than losing it.
Future<bool> restoreDoNotDisturb({
  required SharedPreferences prefs,
  required Future<bool> Function(int filter) setFilter,
}) async {
  final previous = prefs.getInt(doNotDisturbPreviousFilterKey);
  if (previous == null) return false;
  final applied = await setFilter(previous);
  if (applied) {
    await prefs.remove(doNotDisturbPreviousFilterKey);
    await prefs.remove(doNotDisturbActivatedAtKey);
  }
  return applied;
}

/// The safety net (docs/TODO.md T-184): checked during the regular
/// scheduling checkpoint, which already runs on every app open (FR-17)
/// regardless of Do Not Disturb specifically. If Do Not Disturb has been
/// active for longer than [maxDoNotDisturbDuration] - whatever the reason,
/// this never reasons about WHY - it is restored anyway, rather than left
/// silenced indefinitely. A missing activation timestamp (an already-active
/// state stored before this safety net existed, or any other inconsistency)
/// is treated as stale too: the whole point of a safety net is to not
/// require every precondition to hold for it to actually fire.
Future<bool> restoreStaleDoNotDisturb({
  required SharedPreferences prefs,
  required Future<bool> Function(int filter) setFilter,
  DateTime Function()? now,
}) async {
  if (!prefs.containsKey(doNotDisturbPreviousFilterKey)) return false;
  final activatedAtMillis = prefs.getInt(doNotDisturbActivatedAtKey);
  final activatedAt = activatedAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(activatedAtMillis);
  final nowValue = (now ?? DateTime.now)();
  final stale =
      activatedAt == null || nowValue.difference(activatedAt) > maxDoNotDisturbDuration;
  if (!stale) return false;
  return restoreDoNotDisturb(prefs: prefs, setFilter: setFilter);
}

/// The background-isolate entry point (docs/TODO.md T-184):
/// `onNotificationCreatedMethod` calls this when the scheduled bedtime
/// notification (`doNotDisturbActivationNotificationId`,
/// `do_not_disturb_schedule.dart`) is created - mirroring
/// `runTimezoneCheckpoint2`'s own reasoning for reading `SharedPreferences`
/// directly rather than through `AppState`: this isolate has neither
/// `AppState` nor `Provider` access at all.
///
/// [prefs]/[getCurrentFilter]/[setFilter] are all injectable purely for
/// testability - the real defaults ([SharedPreferences.getInstance] and the
/// native platform channel) have no channel in `flutter test`.
Future<void> runDoNotDisturbActivation({
  SharedPreferences? prefs,
  Future<int?> Function()? getCurrentFilter,
  Future<bool> Function(int filter)? setFilter,
}) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    final enabled = p.getBool('doNotDisturbEnabled') ?? false;
    if (!enabled) return;
    await activateDoNotDisturb(
      prefs: p,
      getCurrentFilter: getCurrentFilter ?? getCurrentInterruptionFilter,
      setFilter: setFilter ?? setInterruptionFilter,
    );
  } catch (e) {
    debugPrint("=====runDoNotDisturbActivation: ${e.runtimeType}");
  }
}
