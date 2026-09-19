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
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/next_wake_up.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

/// A fixed notification id for the sleep-time reminder (outside
/// `getRandom()`'s 0..99999999 range, so it can never collide with one of
/// those) - lets [scheduleSleepReminder] cancel and replace exactly its own,
/// single, previous notification every time it re-schedules, rather than
/// `cancelAllNotifications()` (found during an independent Phase 5 review to
/// be a real hazard: `Handler.handleAlarm()`'s unawaited replan checkpoint
/// can schedule an FR-6/FR-9/FR-12 warning notification around the same time
/// a dismiss triggers `onAlarmHandled()` -> this function - a global cancel
/// there could wipe out a warning that was never meant to be touched).
const int sleepReminderNotificationId = 100000001;

/// Phase 5 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge", Schritt
/// 21): schedules the sleep-time notification - always, regardless of
/// [AppState.reminderEnabled] (FR-16 "Voraussetzung": Checkpoint 2 needs a
/// notification hook even when the visible reminder itself is disabled;
/// [sleepReminderContent] decides visible-vs-silent, not whether to schedule
/// at all). Shared by every trigger point that needs this - the reminder
/// toggle, a dismissed alarm, and app cold-start (found missing during an
/// independent Phase 5 review: without it, a fresh install never schedules
/// anything until the toggle is touched or an alarm is dismissed once,
/// leaving Checkpoint 2 without a hook in the meantime) - rather than
/// re-duplicating this computation a third time. [notifications] is
/// injectable purely for testability.
Future<void> scheduleSleepReminder(
  AppState appState, {
  Notifications? notifications,
}) async {
  try {
    DateTime dateTime;
    try {
      // docs/TODO.md T-66: sourced from scheduling-v2's own plan plus the
      // user's manual alarms (see nextWakeUpTime), no longer from the old
      // Scheduler, which Phase 6 removed (docs/TODO.md T-64).
      // Fallback when nothing is planned at all mirrors the old behavior
      // (a week out), which still leaves FR-16 Checkpoint 2 a hook.
      dateTime = nextWakeUpTime(
            pendingDayValues: appState.pendingDayValues,
            manualAlarms: appState.manualAlarms,
            now: DateTime.now(),
          ) ??
          DateTime.now().add(const Duration(days: 7));
    } catch (e) {
      debugPrint("=====scheduleSleepReminder: Error getting next alarm time: ${e.runtimeType}");
      dateTime = DateTime.now();
    }
    try {
      dateTime = dateTime.subtract(durationFromTimeOfDay(appState.sleepGoal));
    } catch (e) {
      debugPrint("=====scheduleSleepReminder: Error subtracting sleepGoal: ${e.runtimeType}");
      dateTime = dateTime.subtract(const Duration(hours: 8));
    }
    try {
      dateTime =
          dateTime.subtract(durationFromTimeOfDay(appState.reminderDuration));
    } catch (e) {
      debugPrint(
          "=====scheduleSleepReminder: Error subtracting reminderDuration: ${e.runtimeType}");
      dateTime = dateTime.subtract(const Duration(minutes: 30));
    }

    // docs/TODO.md T-110: a bedtime in the PAST must not be passed on here.
    //
    // Reachable as soon as `sleepGoal + reminderDuration` is greater than the
    // distance to the next wake instant - e.g.: the user changes a setting at
    // 22:00, the plan says 05:00, sleep goal 9 hours. The trigger
    // `settingsChanged` is not subject to any daily lock, so it runs.
    //
    // What happens then is read from the AAR, not guessed:
    // `CronUtils.getNextCalendar` returns `null` for a fully determined date
    // before "now", `NotificationScheduler.doInBackground` then calls
    // `cancelSchedule`, logs "Date is not more valid." and aborts - the
    // Created event only comes on the non-null branch. The old notification
    // is already cancelled by that point. For that night, FR-16's checkpoint
    // 2 would then have no entry point at all, and a time zone change that
    // happened during the day would only be noticed at the next ring -
    // exactly the scenario the second checkpoint was built against.
    //
    // Two minutes of lead time, not one: `alarmPlatformTime` truncates to
    // whole minutes, so one minute could shrink down to mere seconds.
    //
    // The SPEC does not decide this case - FR-16 only says when the
    // checkpoint should run, not what applies once that instant has passed.
    // The reading chosen is the one closest to FR-16's purpose: catch up the
    // hook as early as possible. It is deliberately NOT made visible while
    // doing so - a "time to sleep" message hours after the intended instant
    // would be misleading, and FR-16 explicitly separates visibility from the
    // hook ("regardless of whether the reminder itself is enabled").
    final missedBedtime = !dateTime.isAfter(DateTime.now());
    if (missedBedtime) {
      dateTime = DateTime.now().add(const Duration(minutes: 2));
    }

    try {
      final notifier = notifications ?? Notifications();
      await notifier.cancelNotification(sleepReminderNotificationId);
      final content = sleepReminderContent(
          reminderEnabled: appState.reminderEnabled && !missedBedtime);
      await notifier.scheduleNotification(
          title: content.title,
          body: content.body,
          // docs/TODO.md T-61: same boundary as the alarm plugin -
          // NotificationCalendar.fromDate reads the DateTime's own fields as a
          // local wall clock, and the bedtime is derived from a planned value
          // that is a UTC-tagged instant. Without converting first, FR-16's
          // Checkpoint 2 would fire at the wrong local time.
          scheduledDate: alarmPlatformTime(dateTime),
          id: sleepReminderNotificationId);
    } catch (e) {
      debugPrint("=====scheduleSleepReminder: scheduleNotification failed: ${e.runtimeType}");
    }
    debugPrint("=====scheduleSleepReminder: Set sleep reminder for $dateTime");
  } catch (e) {
    debugPrint("=====scheduleSleepReminder: Error setting sleep reminder: ${e.runtimeType}");
  }
}
