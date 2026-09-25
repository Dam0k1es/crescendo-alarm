// docs/TODO.md T-176 (maintainer request): a ManualAlarm's own
// `snoozeEnabled` now overrides the global `AppState.snoozeEnabled` once
// set, resolved through the single `effectiveSnoozeEnabled` helper both
// `SnoozeButton`'s visibility check and `snoozeRingingAlarm`'s own internal
// check call - the same "one calculation, not two copies that could drift
// apart" reasoning snooze.dart's own doc comment already gives for why
// `canSnooze` is shared in the first place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/snooze.dart';

void main() {
  group('effectiveSnoozeEnabled', () {
    test('a ManualAlarm\'s own value overrides the global setting', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final appState = AppState();
      await appState.initialized;
      appState.snoozeEnabled = true;

      // Seeded directly rather than via appState.addAlarm(), which also
      // arms the real `alarm` plugin (no platform channel in `flutter
      // test`) - manualAlarms exposes the actual mutable list for exactly
      // this kind of test setup.
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        id: 42,
        snoozeEnabled: false,
      );
      appState.manualAlarms.add(alarm);

      expect(effectiveSnoozeEnabled(appState, 42), isFalse,
          reason: 'the alarm opted out, even though the global setting is on');
    });

    test('falls back to the global setting for an unknown alarm id',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final appState = AppState();
      await appState.initialized;
      appState.snoozeEnabled = false;

      expect(effectiveSnoozeEnabled(appState, 999), isFalse);
    });
  });

  group('snoozeRingingAlarm respects the per-alarm override', () {
    test('refuses to snooze when the alarm has opted out, even though the '
        'global setting is on', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final appState = AppState();
      await appState.initialized;
      appState.snoozeEnabled = true;
      appState.snoozeTime = const Duration(minutes: 5);

      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        id: 7,
        snoozeEnabled: false,
      );
      appState.manualAlarms.add(alarm);

      var setAlarmCalled = false;
      final moved = await snoozeRingingAlarm(
        appState,
        alarmId: 7,
        ringTime: DateTime(2026, 9, 25, 7, 0),
        now: () => DateTime(2026, 9, 25, 7, 1),
        setAlarm: (id, at) async {
          setAlarmCalled = true;
        },
        stopAlarm: (id) async {},
      );

      expect(moved, isFalse);
      expect(setAlarmCalled, isFalse);
    });
  });
}
