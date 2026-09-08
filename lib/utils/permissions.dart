import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsManager {
  Future<void> requestPermissions(BuildContext context) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await checkScheduleExactAlarmPermission();
      await checkCameraPermission();
      await checkCalendarPermission();
      // await checkNotificationPermission();
      await checkAwesomeNotificationPermission();
    }
  }

  Future<void> checkScheduleExactAlarmPermission() async {
    PermissionStatus status = await Permission.scheduleExactAlarm.status;
    if (status.isGranted) {
      debugPrint('Schedule exact alarm permission already granted.');
    } else {
      debugPrint('Requesting schedule exact alarm permission...');
      status = await Permission.scheduleExactAlarm.request();
      if (status.isGranted) {
        debugPrint('Schedule exact alarm permission granted.');
      } else {
        debugPrint('Schedule exact alarm permission not granted.');
      }
    }
  }

  Future<void> checkNotificationPermission() async {
    PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) {
      debugPrint('Notification permission already granted.');
    } else {
      debugPrint('Requesting notification permission...');
      status = await Permission.notification.request();
      if (status.isGranted) {
        debugPrint('Notification permission granted.');
      } else {
        debugPrint('Notification permission not granted.');
      }
    }
  }

  Future<void> checkAwesomeNotificationPermission() async {
    final notifications = AwesomeNotifications();

    final alreadyGranted = await notifications.isNotificationAllowed();
    if (alreadyGranted) {
      debugPrint('=====Awesome_notifications: Permission already granted');
    } else {
      debugPrint('=====Awesome_notifications: Requesting permission...');
      await notifications.requestPermissionToSendNotifications();
      final nowGranted = await notifications.isNotificationAllowed();
      if (nowGranted) {
        debugPrint('=====Awesome_notifications: Permission granted');
      } else {
        debugPrint('=====Awesome_notifications: Permission not granted');
      }
    }
  }

  Future<void> checkCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) {
      debugPrint('Camera permission already granted.');
    } else {
      debugPrint('Requesting camera permission...');
      status = await Permission.camera.request();
      if (status.isGranted) {
        debugPrint('Camera permission granted.');
      } else {
        debugPrint('Camera permission not granted.');
      }
    }
  }

  Future<void> checkCalendarPermission() async {
    PermissionStatus status = await Permission.calendarFullAccess.status;
    if (status.isGranted) {
      debugPrint('Calendar permission already granted.');
    } else {
      debugPrint('Requesting calendar permission...');
      status = await Permission.calendarFullAccess.request();
      if (status.isGranted) {
        debugPrint('Calendar permission granted.');
      } else {
        debugPrint('Calendar permission not granted.');
      }
    }
  }
}
