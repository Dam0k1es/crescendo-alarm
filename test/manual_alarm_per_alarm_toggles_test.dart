// docs/TODO.md T-176 (maintainer request): a ManualAlarm can now override two
// settings that used to be purely global - whether snooze is available at
// all, and whether the deactivation-code (QR) gate applies - on a per-alarm
// basis. Both are properties of the ALARM, the same pattern this file's
// sibling settings (gentlewake, gentleWakeDuration, tone, volume, vibrate)
// already established, but neither feeds `AlarmSettings`/the native platform
// alarm: both are read only at ring time via `AppState.getAlarm`, so this
// file only needs to cover the model itself (construction defaults,
// serialization, equality) - the ring-time resolution is covered by
// test/snooze_per_alarm_override_test.dart and
// test/handler_deactivation_code_override_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';

void main() {
  // Needed by the AppState.addAlarm regression test below, which touches
  // the `alarm` plugin's own platform-channel setup internally.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManualAlarm.snoozeEnabled', () {
    test('defaults to true when not given', () {
      final alarm = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 0));
      expect(alarm.snoozeEnabled, isTrue);
    });

    test('can be explicitly set to false', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        snoozeEnabled: false,
      );
      expect(alarm.snoozeEnabled, isFalse);
    });

    test('survives a toJson/fromJson round trip', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        snoozeEnabled: false,
      );
      final restored = ManualAlarm.fromJson(alarm.toJson());
      expect(restored.snoozeEnabled, isFalse);
    });

    test('missing from stored JSON (pre-T-176 alarm) defaults to true', () {
      final legacyJson = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 0))
          .toJson()
          .replaceFirst(RegExp('"snoozeEnabled":(true|false),'), '');
      final restored = ManualAlarm.fromJson(legacyJson);
      expect(restored.snoozeEnabled, isTrue);
    });
  });

  group('ManualAlarm.requireDeactivationCode', () {
    test('defaults to true when not given - the only behavior that '
        'existed before this override', () {
      final alarm = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 0));
      expect(alarm.requireDeactivationCode, isTrue);
    });

    test('can be explicitly set to false', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        requireDeactivationCode: false,
      );
      expect(alarm.requireDeactivationCode, isFalse);
    });

    test('survives a toJson/fromJson round trip', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        requireDeactivationCode: false,
      );
      final restored = ManualAlarm.fromJson(alarm.toJson());
      expect(restored.requireDeactivationCode, isFalse);
    });

    test('missing from stored JSON (pre-T-176 alarm) defaults to true', () {
      final legacyJson =
          ManualAlarm(time: const TimeOfDay(hour: 7, minute: 0))
              .toJson()
              .replaceFirst(
                  RegExp('"requireDeactivationCode":(true|false),'), '');
      final restored = ManualAlarm.fromJson(legacyJson);
      expect(restored.requireDeactivationCode, isTrue);
    });
  });

  group('ManualAlarm.countsForDoNotDisturb (docs/TODO.md T-191, maintainer '
      'request)', () {
    test('defaults to false - opt-in, unlike snoozeEnabled/'
        'requireDeactivationCode above', () {
      final alarm = ManualAlarm(time: const TimeOfDay(hour: 7, minute: 0));
      expect(alarm.countsForDoNotDisturb, isFalse);
    });

    test('can be explicitly set to true', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        countsForDoNotDisturb: true,
      );
      expect(alarm.countsForDoNotDisturb, isTrue);
    });

    test('survives a toJson/fromJson round trip', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        countsForDoNotDisturb: true,
      );
      final restored = ManualAlarm.fromJson(alarm.toJson());
      expect(restored.countsForDoNotDisturb, isTrue);
    });

    test('missing from stored JSON (pre-T-191 alarm) defaults to false', () {
      final legacyJson = ManualAlarm(
              time: const TimeOfDay(hour: 7, minute: 0),
              countsForDoNotDisturb: true)
          .toJson()
          .replaceFirst(RegExp('"countsForDoNotDisturb":(true|false),'), '');
      final restored = ManualAlarm.fromJson(legacyJson);
      expect(restored.countsForDoNotDisturb, isFalse);
    });
  });

  test('equality considers all three new fields', () {
    final a = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: true,
      requireDeactivationCode: true,
      countsForDoNotDisturb: true,
    );
    final differentSnooze = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: false,
      requireDeactivationCode: true,
      countsForDoNotDisturb: true,
    );
    final differentCode = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: true,
      requireDeactivationCode: false,
      countsForDoNotDisturb: true,
    );
    final differentDnd = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: true,
      requireDeactivationCode: true,
      countsForDoNotDisturb: false,
    );

    expect(a == differentSnooze, isFalse);
    expect(a == differentCode, isFalse);
    expect(a == differentDnd, isFalse);
  });

  test(
      'docs/TODO.md T-191: AppState.addAlarm carries countsForDoNotDisturb '
      'through - the exact "setting with a UI that never reaches the alarm" '
      'bug class T-84/T-176 already hit twice, found here by comparing the '
      'dialog widget\'s own state against what actually got saved', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();
    await appState.initialized;

    final alarm = ManualAlarm(
      time: TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(minutes: 5))),
      // Switched off so this never reaches Alarm.set - FR-21 already
      // established that a disabled alarm is never armed, not even
      // attempted, which is what lets this test avoid the real `alarm`
      // plugin's platform channel (unavailable in `flutter test`).
      enabled: false,
      countsForDoNotDisturb: true,
    );
    final result = await appState.addAlarm(alarm);

    expect(result['success'], isTrue);
    expect(appState.manualAlarms.single.countsForDoNotDisturb, isTrue,
        reason: 'AppState.addAlarm reconstructs a new ManualAlarm from the '
            'one passed in, explicitly listing which fields to carry over - '
            'this one was missing from that list, silently resetting it to '
            'the constructor default regardless of what the dialog saved');
  });
}
