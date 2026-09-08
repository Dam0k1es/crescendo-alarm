import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:wakeywakey/utils/utils.dart';

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
  }

  // Set a notification to be shown at a specific time
  Future<int> scheduleNotification({
    required String title,
    required String body,
    DateTime? scheduledDate,
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

    int random = getRandom();
    bool returnValue;

    if (scheduledDate != null) {
      returnValue = await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: random,
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
          id: random,
          channelKey: 'alerts',
          title: title,
          body: body,
          notificationLayout: NotificationLayout.Default,
        ),
      );
    }

    if (returnValue) {
      return random;
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
