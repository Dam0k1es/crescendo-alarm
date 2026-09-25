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
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';

void main() {
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

  test('equality considers both new fields', () {
    final a = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: true,
      requireDeactivationCode: true,
    );
    final differentSnooze = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: false,
      requireDeactivationCode: true,
    );
    final differentCode = ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      id: 1,
      snoozeEnabled: true,
      requireDeactivationCode: false,
    );

    expect(a == differentSnooze, isFalse);
    expect(a == differentCode, isFalse);
  });
}
