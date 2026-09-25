// docs/TODO.md T-176 (maintainer request): whether the QR/deactivation-code
// gate is shown for a specific ringing alarm now depends on that alarm's own
// `requireDeactivationCode` (when it is a ManualAlarm), not only on whether a
// global code is configured at all. Extracted as a pure function (matching
// isAlarmStale's own precedent in this file) so this decision has a test
// that needs neither a BuildContext nor the real `alarm` plugin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/manual_alarm.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';

void main() {
  group('shouldRequireDeactivationCode', () {
    test('no code configured at all: never required, regardless of alarm',
        () {
      expect(shouldRequireDeactivationCode(null, false), isFalse);
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        requireDeactivationCode: true,
      );
      expect(shouldRequireDeactivationCode(alarm, false), isFalse);
    });

    test('a ManualAlarm that opted out is not gated, even though a code '
        'is configured', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        requireDeactivationCode: false,
      );
      expect(shouldRequireDeactivationCode(alarm, true), isFalse);
    });

    test('a ManualAlarm that did not opt out is gated when a code is '
        'configured', () {
      final alarm = ManualAlarm(
        time: const TimeOfDay(hour: 7, minute: 0),
        requireDeactivationCode: true,
      );
      expect(shouldRequireDeactivationCode(alarm, true), isTrue);
    });

    test('a ScheduledAlarm has no override and follows the global setting',
        () {
      final alarm = ScheduledAlarm(
        time: DateTime(2026, 9, 25, 7, 0).toUtc(),
      );
      expect(shouldRequireDeactivationCode(alarm, true), isTrue);
      expect(shouldRequireDeactivationCode(alarm, false), isFalse);
    });

    test('an id AppState has no record of at all follows the global '
        'setting', () {
      expect(shouldRequireDeactivationCode(null, true), isTrue);
    });
  });
}
