import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/next_wake_up.dart';
import 'package:crescendo_alarm/utils/direct_boot_mirror.dart'
    as direct_boot_mirror;
import 'package:crescendo_alarm/utils/notifications.dart';
import 'package:crescendo_alarm/utils/sleep_reminder.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';
import 'package:crescendo_alarm/utils/utils.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-221: once a switched-off planned day stays in the alarm
// list as an inactive entry (and stays in `pendingDayValues` as FR-21's
// anchor), every reader of either has to know that it does not ring. This
// file holds one case per consumer that is about ringing or waking - the
// audit's result, in test form. A switched-off day must never ring, never
// define the Do Not Disturb sleep time, the bedtime reminder, or the
// direct-boot fallback siren.
//
// Instants are compared via millisecondsSinceEpoch (six-zone CI matrix).

int _ms(DateTime t) => t.millisecondsSinceEpoch;

class _RecordingNotifications implements Notifications {
  DateTime? lastScheduledDate;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    lastScheduledDate = scheduledDate;
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  final now = DateTime.utc(2026, 3, 10, 6, 0);
  final off = DateTime.utc(2026, 3, 11, 5, 0);
  final on = DateTime.utc(2026, 3, 12, 7, 0);
  final values = {'2026-03-11': _ms(off), '2026-03-12': _ms(on)};

  test('nextWakeUpTime skips a switched-off planned day', () {
    final result = nextWakeUpTime(
      pendingDayValues: values,
      disabledDays: {'2026-03-11'},
      manualAlarms: const [],
      now: now,
    );

    expect(result == null ? null : _ms(result), _ms(on));
  });

  test('counter-test: nextWakeUpTime still returns that day while it is on',
      () {
    final result = nextWakeUpTime(
      pendingDayValues: values,
      disabledDays: const {},
      manualAlarms: const [],
      now: now,
    );

    expect(result == null ? null : _ms(result), _ms(off));
  });

  test('sleepTimeWindow (Do Not Disturb) ends at the next ENABLED day', () {
    final window = sleepTimeWindow(
      pendingDayValues: values,
      disabledDays: {'2026-03-11'},
      manualAlarms: const [],
      sleepGoal: const TimeOfDay(hour: 8, minute: 0),
      now: now,
    );

    expect(_ms(window!.end), _ms(alarmPlatformTime(on)));
  });

  group('direct-boot fallback mirror', () {
    DateTime? mirrored;

    setUp(() {
      mirrored = null;
      direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {
        mirrored = dueAt;
      };
    });

    tearDown(() {
      direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {};
    });

    test('a switched-off day is not mirrored as the next due alarm',
        () async {
      // Otherwise a reboot with the phone left locked starts the fallback
      // siren for a day the user switched off.
      final appState = await _fresh();
      appState.pendingDayValues = values;
      appState.setDayEnabled('2026-03-11', false);

      appState.refreshDirectBootFallback(now: () => now);

      expect(mirrored == null ? null : _ms(mirrored!), _ms(on));
    });

    test('counter-test: the day is mirrored while it is on', () async {
      final appState = await _fresh();
      appState.pendingDayValues = values;

      appState.refreshDirectBootFallback(now: () => now);

      expect(mirrored == null ? null : _ms(mirrored!), _ms(off));
    });
  });

  test('the bedtime reminder is timed from the next ENABLED day', () async {
    // scheduleSleepReminder reads the real clock, so the fixture is built
    // relative to it.
    final appState = await _fresh();
    final realNow = DateTime.now();
    final tomorrow = realNow.add(const Duration(days: 1));
    final dayAfter = realNow.add(const Duration(days: 2));
    appState.pendingDayValues = {
      isoDate(tomorrow): _ms(tomorrow),
      isoDate(dayAfter): _ms(dayAfter),
    };
    appState.setDayEnabled(isoDate(tomorrow), false);
    final notifications = _RecordingNotifications();

    await scheduleSleepReminder(appState, notifications: notifications);

    final expected = alarmPlatformTime(dayAfter
        .subtract(durationFromTimeOfDay(appState.sleepGoal))
        .subtract(durationFromTimeOfDay(appState.reminderDuration)));
    expect(_ms(notifications.lastScheduledDate!), _ms(expected),
        reason: 'a reminder computed from a day that will not ring sends the '
            'user to bed for a wake-up that never comes (FR-21)');
  });

  test('Handler.onAlarmHandled never arms a disabled ScheduledAlarm',
      () async {
    final appState = await _fresh();
    final platform = FakeAlarmPlatform()..attach(appState);
    appState.scheduledAlarms = [
      ScheduledAlarm(time: off.toLocal(), enabled: false, id: 3),
    ];
    final rearmed = <int>[];

    Handler.onAlarmHandled(
      appState,
      3,
      notifications: _RecordingNotifications(),
      setManualAlarmEnabled: (alarm, enabled) async {
        rearmed.add(alarm.id);
        return true;
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(rearmed, isEmpty);
    expect(platform.setIds, isEmpty);
  });
}
