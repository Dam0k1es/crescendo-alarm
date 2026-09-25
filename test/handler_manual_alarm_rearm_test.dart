import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

// docs/TODO.md T-14, continued: honouring `repeatOnDays` when computing the
// NEXT occurrence (manual_alarm_repeat_test.dart) only fires the alarm once
// on the first matching day, because the platform alarm itself is one-shot -
// without also re-arming for the day after, "repeat on Mon/Wed/Fri" would
// still only ever ring once, on whichever of those came first. Real
// recurrence requires re-arming on every dismiss, so `Handler.onAlarmHandled`
// - the one place every dismissal path (Stop button, QR gate, and the T-147
// auto-close) already funnels through - now does that for a ManualAlarm.
//
// `setManualAlarmEnabled` is injectable here for the same reason
// `runCheckpoint` is on `Handler` itself: `AppState.setManualAlarmEnabled`
// calls the real `alarm` plugin, which has no channel in `flutter test`.

class _SilentNotifications implements Notifications {
  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async =>
      id ?? 1;

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

ManualAlarm _manualAlarm({int id = 1, bool enabled = true}) => ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: id,
    );

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a ringing ManualAlarm is re-armed for its next occurrence', () async {
    final appState = await _freshAppState();
    appState.manualAlarms.add(_manualAlarm());
    final rearmed = <int>[];

    Handler.onAlarmHandled(
      appState,
      1,
      notifications: _SilentNotifications(),
      setManualAlarmEnabled: (alarm, enabled) async {
        rearmed.add(alarm.id);
        return true;
      },
    );
    await _settle();

    expect(rearmed, [1],
        reason: 'repeat only works if the alarm is re-armed on every '
            'dismiss - a one-shot platform alarm cannot repeat itself');
  });

  test('a switched-off ManualAlarm is not re-armed', () async {
    final appState = await _freshAppState();
    appState.manualAlarms.add(_manualAlarm(enabled: false));
    final rearmed = <int>[];

    Handler.onAlarmHandled(
      appState,
      1,
      notifications: _SilentNotifications(),
      setManualAlarmEnabled: (alarm, enabled) async {
        rearmed.add(alarm.id);
        return true;
      },
    );
    await _settle();

    expect(rearmed, isEmpty,
        reason: 'this should not be reachable in practice (a disabled alarm '
            'is not armed at the platform and so cannot ring), but the '
            'flag must be respected defensively');
  });

  test('a ringing ScheduledAlarm is not treated as a manual repeat', () async {
    final appState = await _freshAppState();
    appState.scheduledAlarms = [
      ScheduledAlarm(
        time: DateTime.now().add(const Duration(minutes: 1)),
        enabled: true,
        gentlewake: false,
        tone: 'assets/sounds/lollipop.mp3',
        id: 1,
      ),
    ];
    var called = false;

    Handler.onAlarmHandled(
      appState,
      1,
      notifications: _SilentNotifications(),
      setManualAlarmEnabled: (alarm, enabled) async {
        called = true;
        return true;
      },
    );
    await _settle();

    expect(called, isFalse,
        reason: 'ScheduledAlarms are FR-18\'s domain - re-arming one here '
            'would be a second, conflicting scheduling path');
  });

  test('an unknown alarm id does not throw', () async {
    final appState = await _freshAppState();
    var called = false;

    expect(
      () => Handler.onAlarmHandled(
        appState,
        999,
        notifications: _SilentNotifications(),
        setManualAlarmEnabled: (alarm, enabled) async {
          called = true;
          return true;
        },
      ),
      returnsNormally,
    );
    await _settle();

    expect(called, isFalse);
  });
}
