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
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/utils/do_not_disturb.dart';
import 'package:crescendo_alarm/utils/do_not_disturb_channel.dart';
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart';
import 'package:crescendo_alarm/utils/utils.dart';

/// A fixed notification id for the Do Not Disturb activation hook
/// (docs/TODO.md T-184) - the same "cancel and replace exactly this one"
/// reasoning as [sleepReminderNotificationId], and deliberately a different
/// id from it: activation fires at the bedtime instant itself
/// (wakeTime - sleepGoal), while the reminder fires earlier still
/// (wakeTime - sleepGoal - reminderDuration) - two different instants,
/// two independently scheduled/cancelled notifications.
const int doNotDisturbActivationNotificationId = 100000002;

/// Schedules (or cancels) the silent notification that triggers Do Not
/// Disturb activation at bedtime, mirroring [scheduleSleepReminder]'s own
/// structure closely - the same background-notification mechanism
/// (`onNotificationCreatedMethod` branches on which fixed id fired), the
/// same past-bedtime handling (T-110), just a different instant and a
/// binary on/off rather than visible-vs-silent.
///
/// Deliberately at [bedtimeInstant] directly, NOT further reduced by
/// [AppState.reminderDuration] - the maintainer's own wording, "vor dem
/// Wecker (ohne reminder Zeit)": notifications go quiet at the actual
/// sleep-goal-derived bedtime, not already at the earlier lead-time
/// reminder.
///
/// Also persists the WAKE-UP instant this bedtime was computed from
/// (docs/TODO.md T-184, independent review finding) - [bedtimeInstant]
/// itself only returns the bedtime, so the wake-up is recovered by adding
/// [AppState.sleepGoal] back. `Handler.handleAlarm` reads this later
/// (`isTargetWakeUpRing`) to tell whether a given ring is the one Do Not
/// Disturb was actually scheduled around, as opposed to some unrelated
/// alarm that merely happens to ring and become final first. Cleared (not
/// just left stale) whenever Do Not Disturb is disabled, so turning it back
/// on later can never compare against a target from before the gap.
///
/// docs/TODO.md T-189 (maintainer request, superseding T-188's own first
/// attempt): the maintainer's own definition is simpler than either of this
/// function's earlier designs and is what's implemented here directly -
/// "in der schlafenszeit automatisch aktiviert und danach deaktiviert...
/// die schlafenszeit ist die zeit die konfiguriert ist VOR dem nächsten
/// alarm" (during sleep time - the configured time BEFORE the next alarm -
/// automatically activated, and deactivated afterward). Sleep time is
/// therefore the half-open window `[bedtime, wakeUp)`, and this function
/// evaluates that window LIVE, on every call, rather than only reacting to
/// a precisely-timed background notification:
///  - **`now` inside the window** -> activate right now (idempotent - a
///    no-op if already active). This is what makes a short-turnaround
///    schedule (the next wake-up sooner than the configured Sleep Goal -
///    the exact shape T-188 first mis-handled by skipping entirely) work
///    correctly: if the window has already started, being inside it IS
///    the correct state to converge to, immediately, regardless of how
///    long ago it technically started.
///  - **`now` at or after the window's own end** -> restore, if this
///    feature is still the reason Do Not Disturb is on. This is a second,
///    independent path to the same restore `Handler.handleAlarm`'s
///    final-ring check and `Handler.onAlarmHandled`'s Stop-time check
///    already provide (docs/TODO.md T-184/T-186) - a safety net tied to
///    the window's own precise end, tighter than the 18-hour
///    [restoreStaleDoNotDisturb] cap, not a replacement for either.
///  - **`now` still before the window** -> nothing to do live; a
///    notification is armed so activation still happens later even if the
///    app isn't running when bedtime arrives.
///
/// The notification itself is only touched when the target this schedule
/// is actually FOR has changed (or none is armed yet) - re-running this
/// function on every checkpoint trigger (a settings change, a calendar
/// resync, the alarm-list sync button - none of which imply the sleep
/// cycle itself changed) used to unconditionally cancel whatever was
/// already correctly armed, silently disarming a night's activation the
/// moment the user did anything else in the app that evening (found during
/// independent review of T-188's first attempt).
///
/// [prefs]/[now]/[getCurrentFilter]/[setFilter] are all injectable purely
/// for testability, matching this project's established pattern elsewhere.
Future<void> scheduleDoNotDisturbActivation(
  AppState appState, {
  Notifications? notifications,
  SharedPreferences? prefs,
  DateTime Function()? now,
  Future<int?> Function()? getCurrentFilter,
  Future<bool> Function(int filter)? setFilter,
}) async {
  try {
    final notifier = notifications ?? Notifications();
    final p = prefs ?? await SharedPreferences.getInstance();
    final nowFn = now ?? DateTime.now;
    final currentNow = nowFn();
    final getFilter = getCurrentFilter ?? getCurrentInterruptionFilter;
    final setFilterFn = setFilter ?? setInterruptionFilter;

    if (!appState.doNotDisturbEnabled) {
      await notifier.cancelNotification(doNotDisturbActivationNotificationId);
      await p.remove(doNotDisturbTargetWakeUpKey);
      return;
    }

    // Step 1: has whatever cycle was PREVIOUSLY persisted (if any) already
    // ended? Checked against the OLD, already-stored target - never a
    // freshly recomputed one, which [nextWakeUpTime] guarantees is always
    // still in the future ("the NEXT wake-up" is meaningless otherwise), so
    // a fresh target could never be found "ended" this way. This is what
    // actually detects a genuinely-elapsed night and restores it, tighter
    // and more immediate than the 18-hour [restoreStaleDoNotDisturb] cap -
    // a second, independent path to the same restore `Handler.handleAlarm`/
    // `Handler.onAlarmHandled` already provide.
    var previousTargetMillis = p.getInt(doNotDisturbTargetWakeUpKey);
    if (previousTargetMillis != null &&
        !currentNow.isBefore(
            DateTime.fromMillisecondsSinceEpoch(previousTargetMillis))) {
      if (p.containsKey(doNotDisturbPreviousFilterKey)) {
        await restoreDoNotDisturb(prefs: p, setFilter: setFilterFn);
      }
      await p.remove(doNotDisturbTargetWakeUpKey);
      previousTargetMillis = null;
    }

    // Step 2: the current/next cycle, always freshly recomputed and always
    // a genuinely future wake-up (see above) - so "inside the window"
    // reduces to "has this cycle's bedtime arrived yet".
    final rawBedtime = bedtimeInstant(appState, now: nowFn);
    final targetWakeUp =
        rawBedtime.add(durationFromTimeOfDay(appState.sleepGoal));
    final targetMillis = targetWakeUp.millisecondsSinceEpoch;
    final insideWindow = !currentNow.isBefore(rawBedtime);

    await p.setInt(doNotDisturbTargetWakeUpKey, targetMillis);

    if (insideWindow) {
      // docs/TODO.md T-189 (maintainer request): being inside the
      // configured window IS the correct state to converge to right now,
      // regardless of how long ago it technically started - this is what
      // makes a short-turnaround schedule (next wake-up sooner than the
      // configured Sleep Goal) activate correctly instead of silently
      // never activating at all (T-188's first attempt's own defect).
      await activateDoNotDisturb(
        prefs: p,
        getCurrentFilter: getFilter,
        setFilter: setFilterFn,
        now: nowFn,
      );
      // Already active (or just activated) - nothing left to schedule for
      // an instant that's already in the past.
      await notifier.cancelNotification(doNotDisturbActivationNotificationId);
      return;
    }

    if (previousTargetMillis == targetMillis) {
      // Already correctly armed for this exact target - leave it alone
      // (the regression an independent review found in T-188's first
      // attempt: any unrelated checkpoint trigger re-running this must not
      // disturb an already-correct night's schedule).
      return;
    }

    await notifier.cancelNotification(doNotDisturbActivationNotificationId);
    try {
      // docs/TODO.md T-61: same boundary as the alarm plugin and the sleep
      // reminder itself - the bedtime is derived from a planned value that
      // is a UTC-tagged instant, so it's converted to local wall clock
      // before being handed to the notification scheduler.
      await notifier.scheduleNotification(
          scheduledDate: alarmPlatformTime(rawBedtime),
          id: doNotDisturbActivationNotificationId);
    } catch (e) {
      debugPrint(
          "=====scheduleDoNotDisturbActivation: scheduleNotification failed: ${e.runtimeType}");
    }
    debugPrint(
        "=====scheduleDoNotDisturbActivation: Set Do Not Disturb activation for $rawBedtime");
  } catch (e) {
    debugPrint(
        "=====scheduleDoNotDisturbActivation: Error setting Do Not Disturb activation: ${e.runtimeType}");
  }
}
