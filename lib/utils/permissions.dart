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

import 'dart:io';

import 'package:awesome_notifications/awesome_notifications.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Maintainer request (2026-09-20): camera and calendar access should be
/// requested only when actually needed, not unconditionally at first launch
/// alongside the exact-alarm/notification permissions every alarm needs
/// regardless of which features get used. [QrScanner] (both the initial
/// code-import flow and the alarm-deactivation flow share it) and the
/// Schedule tab/"Sync Alarms" button call these directly instead of going
/// through [PermissionsManager.requestPermissions].
///
/// Top-level, mutable function variables - the same shape as this project's
/// other top-level seams (e.g. `mirrorDirectBootFallback`,
/// `pushSleepTimeWindow`) - rather than a constructor parameter, because production code
/// (`Handler.handleAlarm`) constructs `QrScanner()` directly with no natural
/// place to thread one through, and because the Schedule tab's and the
/// alarms screen's "Sync Alarms" button both need the exact same
/// calendar-permission request, not two independent copies of it.
/// Production code calls the mutable variables; the "...Default" functions
/// are their real implementations, public so a test that overrides a
/// variable can restore it afterwards.
Future<void> requestCameraPermissionDefault() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await PermissionsManager().checkCameraPermission();
  }
}

Future<void> Function() requestCameraPermission = requestCameraPermissionDefault;

Future<void> requestCalendarPermissionDefault() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await PermissionsManager().checkCalendarPermission();
  }
}

Future<void> Function() requestCalendarPermission =
    requestCalendarPermissionDefault;

/// docs/TODO.md T-198: Android's "Do Not Disturb access" (the special
/// `ACCESS_NOTIFICATION_POLICY` grant - a Settings screen, not a runtime
/// dialog). Requested only when the user switches the Sleep Habits Do Not
/// Disturb trigger on, never at startup - the same "only when actually
/// needed" rule as camera and calendar above. `permission_handler` opens the
/// system screen with `startActivityForResult` and resolves once the user
/// comes back, so the returned value is the real state after that visit.
/// `false` off Android: there is no Do Not Disturb to control on the Linux
/// dev loop.
Future<bool> requestDoNotDisturbAccessDefault() async {
  if (!Platform.isAndroid) return false;
  try {
    if (await Permission.accessNotificationPolicy.isGranted) return true;
    return (await Permission.accessNotificationPolicy.request()).isGranted;
  } catch (e) {
    debugPrint('=====requestDoNotDisturbAccess: ${e.runtimeType}');
    return false;
  }
}

Future<bool> Function() requestDoNotDisturbAccess =
    requestDoNotDisturbAccessDefault;

class PermissionsManager {
  /// docs/TODO.md T-41-adjacent (maintainer request, 2026-09-20): camera and
  /// calendar access moved out of this upfront batch - see
  /// [requestCameraPermission]/[requestCalendarPermission] above. Exact-alarm
  /// and notification permissions stay here: an alarm clock needs both from
  /// the moment it can schedule anything, not lazily once some other screen
  /// happens to be opened.
  Future<void> requestPermissions(BuildContext context) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await checkScheduleExactAlarmPermission();
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
