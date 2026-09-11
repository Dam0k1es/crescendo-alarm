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

    // docs/TODO.md T-110: eine Bettzeit in der VERGANGENHEIT darf hier nicht
    // weitergereicht werden.
    //
    // Erreichbar, sobald `sleepGoal + reminderDuration` groesser ist als der
    // Abstand bis zum naechsten Weckzeitpunkt - etwa: der Nutzer aendert um
    // 22:00 eine Einstellung, geplant ist 05:00, Schlafziel 9 Stunden. Der
    // Auslöser `settingsChanged` unterliegt keiner Tagessperre, laeuft also.
    //
    // Was dann passiert, ist im AAR nachgelesen, nicht vermutet:
    // `CronUtils.getNextCalendar` liefert fuer ein vollstaendig bestimmtes
    // Datum vor "jetzt" `null`, `NotificationScheduler.doInBackground` ruft
    // daraufhin `cancelSchedule`, loggt "Date is not more valid." und bricht
    // ab - das Created-Ereignis kommt nur im Nicht-null-Zweig. Die alte
    // Notification ist zu dem Zeitpunkt schon storniert. Fuer diese Nacht
    // haette FR-16s Checkpoint 2 damit gar keinen Einsprungpunkt mehr, und ein
    // untertags eingetretener Zeitzonenwechsel faellt erst beim Klingeln auf -
    // genau das Szenario, gegen das der zweite Checkpoint gebaut wurde.
    //
    // Zwei Minuten Vorlauf, nicht eine: `alarmPlatformTime` schneidet auf
    // ganze Minuten ab, eine Minute koennte dabei bis auf Sekunden
    // zusammenschrumpfen.
    //
    // Die SPEC entscheidet diesen Fall nicht - FR-16 sagt nur, wann der
    // Checkpoint laufen soll, nicht was gilt, wenn dieser Zeitpunkt vorbei
    // ist. Gewaehlt ist die Lesart, die FR-16s Zweck am naechsten kommt: den
    // Aufhaenger so frueh wie moeglich nachholen. Sichtbar ist er dabei
    // bewusst NICHT - eine "Zeit zu schlafen"-Meldung Stunden nach dem
    // gemeinten Zeitpunkt waere irrefuehrend, und FR-16 trennt Sichtbarkeit
    // ausdruecklich vom Aufhaenger ("unabhaengig davon, ob die Erinnerung
    // aktiviert ist").
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
