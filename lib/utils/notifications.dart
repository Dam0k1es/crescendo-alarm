import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/utils.dart';

/// FR-16 Checkpoint 2 / Phase 5 step 22 (docs/scheduling-v2-spec.md): fires
/// whenever ANY notification is created - including the silent, title/body-less
/// "background notification" `sleepReminderContent(reminderEnabled: false)`
/// produces (step 21) - **not** `onNotificationDisplayedMethod`, which only
/// fires for a notification that actually appears in the status bar. Runs in
/// its own background isolate with no `AppState`/`Provider` access, hence
/// [runTimezoneCheckpoint2] (not [runAlarmRingCheckpoint]) - see that
/// function's own doc comment for why it talks to `SharedPreferences`
/// directly instead.
///
/// `@pragma('vm:entry-point')` is required by `awesome_notifications` itself
/// for any listener that must survive being invoked from a fresh background
/// isolate rather than the running app's own.
@pragma('vm:entry-point')
Future<void> onNotificationCreatedMethod(
    ReceivedNotification receivedNotification) async {
  // docs/TODO.md T-89: der Einstiegspunkt dieses Isolates ist die einzige
  // richtige Stelle fuer `Diag.init` - es setzt globalen Zustand (Prefs-Handle
  // und Isolate-Kennung), und dieses Isolate hat seinen eigenen, anderen
  // Ringpuffer als das Haupt-Isolate (dieselbe Falle wie T-69, nur eine Ebene
  // tiefer). Deshalb ein eigener Prefs-Schluessel und ein Merge beim Lesen.
  try {
    await Diag.init(isolate: LogIsolate.background);
  } catch (e) {
    // Ohne Logger laeuft der Checkpoint trotzdem - er ist die Hauptaufgabe.
    debugPrint("=====onNotificationCreatedMethod: Diag.init failed: ${e.runtimeType}");
  }
  await runTimezoneCheckpoint2();
}

/// Required by `AwesomeNotifications().setListeners` (`onActionReceivedMethod`
/// has no default and is not optional) - scheduling-v2 has no use for
/// notification actions/taps, so this is an intentional no-op.
@pragma('vm:entry-point')
Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {}

/// FR-16 "Voraussetzung, noch zu bauen" (docs/scheduling-v2-spec.md): the
/// sleep-time notification must always be scheduled (Phase 5 step 21) so
/// Checkpoint 2 has something to hang off of even when the visible reminder
/// itself is disabled - deciding whether it's visible or not is orthogonal to
/// whether it gets scheduled at all. A [NotificationContent] with neither
/// `title` nor `body` set is created but never shown to the user (a
/// "background notification", per that class's own doc comment) - exactly
/// what's needed to still wake `onNotificationCreatedMethod` (step 22).
({String? title, String? body}) sleepReminderContent({required bool reminderEnabled}) {
  return reminderEnabled
      ? (title: 'Sleep time', body: "It's time to go to sleep")
      : (title: null, body: null);
}

class Notifications {
  // Initialise the awesome_notifications library
  Future<void> init() async {
    await Alarm.init();
    await AwesomeNotifications().initialize(
      null, // icon
      [
        NotificationChannel(
          channelKey: 'alerts',
          channelName: 'Alerts',
          channelDescription: 'Notification channel for alerts',
          defaultColor: Colors.blue,
          ledColor: Colors.white,
          importance: NotificationImportance.High,
        ),
      ],
    );
    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
      onNotificationCreatedMethod: onNotificationCreatedMethod,
    );
  }

  // Set a notification to be shown at a specific time. `title`/`body` are
  // nullable - omitting both creates a silent "background notification"
  // (see `sleepReminderContent`'s doc comment) instead of a visible one.
  // `id` is optional - a fixed id lets a caller later cancel/replace exactly
  // this notification (see `cancelNotification`) without affecting any other;
  // omitting it (the default, used by every caller that doesn't need to
  // revise a specific earlier notification) picks a fresh random one.
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      debugPrint("=====scheduleNotification: isAllowed: $isAllowed");
      return -1;
    } else {
      if (scheduledDate != null) {
        debugPrint(
            "=====scheduleNotification: Scheduling notification for $scheduledDate");
      }
    }

    int notificationId = id ?? getRandom();
    bool returnValue;

    if (scheduledDate != null) {
      returnValue = await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: 'alerts',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
        ),
        schedule: NotificationCalendar.fromDate(
          date: scheduledDate.add(const Duration(seconds: 1)),
          preciseAlarm: true,
        ),
      );
    } else {
      returnValue = await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: 'alerts',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
        ),
      );
    }

    if (returnValue) {
      return notificationId;
    } else {
      return -1;
    }
  }

  // Cancel notification by id
  Future<void> cancelNotification(int id) async {
    debugPrint("=====cancelNotification: Cancelling notification with id: $id");
    return AwesomeNotifications().cancel(id);
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    debugPrint("=====cancelAllNotifications: Cancelling all notifications");
    return AwesomeNotifications().cancelAll();
  }
}
