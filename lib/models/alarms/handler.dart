import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/scheduling.dart';
import 'package:wakeywakey/screens/alarms/screen_active_alarm.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/utils.dart';

/// Whether an alarm's scheduled [eventDateTime] is already in the past
/// relative to [now]. Compares full DateTimes (not just day/hour/minute) so
/// a stale alarm from a previous day/month/year is correctly detected too;
/// both are truncated to minute precision, as the alarm plugin may trigger
/// an alarm a few milliseconds before or after the scheduled time.
bool isAlarmStale(DateTime eventDateTime, DateTime now) {
  final eventMinute = DateTime(eventDateTime.year, eventDateTime.month,
      eventDateTime.day, eventDateTime.hour, eventDateTime.minute);
  final nowMinute =
      DateTime(now.year, now.month, now.day, now.hour, now.minute);
  return eventMinute.isBefore(nowMinute);
}

class Handler {
  final BuildContext _context;
  late final AppState _appState;

  Handler(this._context) {
    _appState = Provider.of<AppState>(_context, listen: false);
  }

  Future<void> handleAlarm(AlarmSettings event) async {
    Notifications notifications = Notifications();

    if (kDebugMode) {
      try {
        String alarmType = "Unknown";
        MyAlarm? appStateAlarm;

        // Get alarm type for debug purposes
        try {
          appStateAlarm = _appState.getAlarm(event.id);
          if (appStateAlarm is ManualAlarm) {
            alarmType = "Manual";
          }
          if (appStateAlarm is ScheduledAlarm) {
            alarmType = "Scheduled";
          }
        } catch (e) {
          debugPrint("=====handleAlarm: Error determining alarm type: $e");
        }

        // Notification with event data for debug purposes
        try {
          notifications.scheduleNotification(
              title: 'WakeyWakey - Event Data',
              body:
                  "Alarm Type: $alarmType, DateTime ${event.dateTime}, ID ${event.id}, Vibrate ${event.vibrate}, Notification on kill ${event.warningNotificationOnKill}");
        } catch (e) {
          debugPrint(
              "=====handleAlarm: Debug notification with event data failed: $e");
        }

        // Notification with appState data for debug purposes
        if (appStateAlarm != null) {
          try {
            notifications.scheduleNotification(
                title: 'WakeyWakey - AppState Data',
                body:
                    "Alarm Type: $alarmType, Time ${appStateAlarm.time}, ID ${appStateAlarm.id}");
          } catch (e) {
            debugPrint(
                "=====handleAlarm: Debug notification with appState data failed: $e");
          }
        }
      } catch (e) {
        debugPrint("=====handleAlarm: Debug message notification failed $e");
      }

      try {
        debugPrint(
            "=====handleAlarm: Alarm with ${event.id} was triggered on ${DateTime.now()} (set on ${event.dateTime})");
      } catch (e) {
        debugPrint("=====handleAlarm: Failed to get alarm settings: $e");
      }
    }

    bool stoppingAlarmPossible = true;

    try {
      // Check if the alarm is set in the past
      bool alarmSetBeforeNow = false;
      try {
        alarmSetBeforeNow = isAlarmStale(event.dateTime, DateTime.now());
      } catch (e) {
        debugPrint(
            "=====handleAlarm: Failed to check if alarm is set in the past: $e");
      }

      // If the event is in the past, stop it
      if (alarmSetBeforeNow) {
        debugPrint("=====handleAlarm: Stopping alarm that is set in the past");
        try {
          Alarm.stop(event.id);
        } catch (e) {
          debugPrint("=====handleAlarm: Failed to stop alarm: $e");
          stoppingAlarmPossible = false;
        }

        // Double check if alarm is still in the list of AlarmSettings
        try {
          List<AlarmSettings> alarmSettings = await Alarm.getAlarms();
          if (!alarmSettings.contains(event)) {
            return;
          }
        } catch (e) {
          debugPrint("=====handleAlarm: Failed to get alarms list: $e");
        }
      }

      // If the event is in the future or now, show either the default alarm overlay or the QR code scanner

      // Check if the deactivation code is set
      bool isDeactivationCodeSet = false;
      try {
        isDeactivationCodeSet = _appState.deactivationCode != null;
      } catch (e) {
        debugPrint(
            "=====handleAlarm: Failed to check if deactivation code is set: $e");
      }

      // If the deactivation code is not set, show the alarm overlay
      if (!isDeactivationCodeSet) {
        debugPrint("=====handleAlarm: _appState.deactivationCode is null");
        try {
          if (!_context.mounted) {
            throw StateError('Context is no longer mounted');
          }
          showFullScreenOverlay(_context, ScreenAlarmActive(alarmId: event.id));
        } catch (e) {
          debugPrint(
              "=====handleAlarm: showFullScreenOverlay (ScreenAlarmActive) failed: $e");
          stoppingAlarmPossible = false;
        }
      }
      // If the deactivation code is set, show the QR code scanner
      else {
        debugPrint("=====handleAlarm: _appState.deactivationCode is set");
        try {
          if (!_context.mounted) {
            throw StateError('Context is no longer mounted');
          }
          showFullScreenOverlay(_context, const QrScanner());
        } catch (e) {
          debugPrint(
              "=====handleAlarm: showFullScreenOverlay (QrScanner) failed: $e");
          stoppingAlarmPossible = false;
        }
      }
    } catch (e) {
      debugPrint("=====handleAlarm: Error handling alarm: $e");
    }

    // If no overlay can be shown, stop all alarms after 3 seconds (to ring in any case)
    if (!stoppingAlarmPossible) {
      try {
        await Future.delayed(const Duration(seconds: 3));
        Alarm.stopAll();
      } catch (e) {
        debugPrint("=====handleAlarm: Failed to stop all alarms: $e");
      }
    }
  }

  static void onAlarmHandled(AppState appState, int alarmID) {
    // Reschedule alarms if rescheduleOnAlarm is set. The setting itself has no
    // UI to change it yet - see docs/TODO.md T-42.
    try {
      Scheduler scheduler = Scheduler();
      if (appState.rescheduleOnAlarm) {
        // Iterate over a copy: scheduleAlarms() removes every entry from
        // appState.scheduledAlarms (the live backing list) as part of
        // rescheduling, which would otherwise throw a
        // ConcurrentModificationError on this very loop.
        List<ScheduledAlarm> scheduledAlarmsSnapshot =
            List<ScheduledAlarm>.from(appState.scheduledAlarms);
        for (ScheduledAlarm alarm in scheduledAlarmsSnapshot) {
          if (alarmID == alarm.id) {
            scheduler.scheduleAlarms(appState);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("=====handleAlarm: scheduleAlarms failed: $e");
    }

// Reschedule sleep time reminder if reminderEnabled is set
    try {
      if (appState.reminderEnabled) {
        DateTime dateTime = Scheduler.nextAlarmTime(appState);
        dateTime = dateTime.subtract(durationFromTimeOfDay(appState.sleepGoal));
        dateTime =
            dateTime.subtract(durationFromTimeOfDay(appState.reminderDuration));
        try {
          Notifications notifications = Notifications();
          notifications.scheduleNotification(
              title: 'Sleep time',
              body: "It's time to go to sleep",
              scheduledDate: dateTime);
        } catch (e) {
          debugPrint(
              "=====handleAlarm: scheduleNotification failed for sleep reminder: $e");
        }
      } else {
        debugPrint("=====handleAlarm: reminder disabled");
      }
    } catch (e) {
      debugPrint("=====handleAlarm: Error rescheduling sleep reminder: $e");
    }
  }
}
