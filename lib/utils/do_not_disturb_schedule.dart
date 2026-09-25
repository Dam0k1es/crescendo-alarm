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
import 'package:crescendo_alarm/app_state.dart';
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
Future<void> scheduleDoNotDisturbActivation(
  AppState appState, {
  Notifications? notifications,
}) async {
  try {
    final notifier = notifications ?? Notifications();
    await notifier.cancelNotification(doNotDisturbActivationNotificationId);

    if (!appState.doNotDisturbEnabled) return;

    final dateTime =
        pushIntoFutureIfPast(bedtimeInstant(appState), DateTime.now());

    try {
      // docs/TODO.md T-61: same boundary as the alarm plugin and the sleep
      // reminder itself - the bedtime is derived from a planned value that
      // is a UTC-tagged instant, so it's converted to local wall clock
      // before being handed to the notification scheduler.
      await notifier.scheduleNotification(
          scheduledDate: alarmPlatformTime(dateTime),
          id: doNotDisturbActivationNotificationId);
    } catch (e) {
      debugPrint(
          "=====scheduleDoNotDisturbActivation: scheduleNotification failed: ${e.runtimeType}");
    }
    debugPrint(
        "=====scheduleDoNotDisturbActivation: Set Do Not Disturb activation for $dateTime");
  } catch (e) {
    debugPrint(
        "=====scheduleDoNotDisturbActivation: Error setting Do Not Disturb activation: ${e.runtimeType}");
  }
}
