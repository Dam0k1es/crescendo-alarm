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

    try {
      final notifier = notifications ?? Notifications();
      await notifier.cancelNotification(sleepReminderNotificationId);
      final content =
          sleepReminderContent(reminderEnabled: appState.reminderEnabled);
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
