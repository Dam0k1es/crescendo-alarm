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
/// [prefs] is injectable purely for testability, matching this project's
/// established pattern elsewhere.
Future<void> scheduleDoNotDisturbActivation(
  AppState appState, {
  Notifications? notifications,
  SharedPreferences? prefs,
}) async {
  try {
    final notifier = notifications ?? Notifications();
    await notifier.cancelNotification(doNotDisturbActivationNotificationId);

    final p = prefs ?? await SharedPreferences.getInstance();
    if (!appState.doNotDisturbEnabled) {
      await p.remove(doNotDisturbTargetWakeUpKey);
      return;
    }

    final rawBedtime = bedtimeInstant(appState);

    // docs/TODO.md T-188 (maintainer device report): unlike
    // scheduleSleepReminder's own T-110 "catch up ASAP" handling
    // (pushIntoFutureIfPast -> now + 2 minutes) - which is harmless there,
    // since a missed bedtime already suppresses that notification's visible
    // content and its only job is keeping FR-16 Checkpoint 2's hook alive -
    // Do Not Disturb activation is a real, immediate effect on the device.
    // Catching it up "as soon as possible" would silence the phone right
    // now, mid-day, whenever the checkpoint happens to run with the next
    // wake-up sooner than the configured sleep goal - not bedtime by any
    // reasonable reading, just an artifact of the algorithm. So a missed
    // bedtime is simply skipped for this cycle instead: the notification
    // was already cancelled above, and the next checkpoint trigger
    // recomputes a genuine future window once one actually exists. Nothing
    // else depends on this notification firing regardless (unlike the
    // reminder's dual Checkpoint-2-hook purpose), so there is no reason to
    // force one here.
    if (!rawBedtime.isAfter(DateTime.now())) {
      await p.remove(doNotDisturbTargetWakeUpKey);
      debugPrint(
          "=====scheduleDoNotDisturbActivation: bedtime $rawBedtime already "
          "passed - not activating Do Not Disturb outside a real sleep window");
      return;
    }

    final targetWakeUp =
        rawBedtime.add(durationFromTimeOfDay(appState.sleepGoal));
    await p.setInt(
        doNotDisturbTargetWakeUpKey, targetWakeUp.millisecondsSinceEpoch);

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
