// An alarm whose due time lies too far in the past must be recognized as
// stale so Handler.handleAlarm stops it instead of showing an overlay. This is
// pure logic with no UI/device dependency, so a plain unit test is more
// appropriate than a full integration_test - see integration_test/app_test.dart
// for the device-driven scenarios, and docs/TODO.md for the full E2E coverage
// picture.
//
// docs/TODO.md T-232: "too far" is T-217's overdue window (the maintainer's
// "Nur bis 60 Min überfällig"), not one minute. The one-minute rule silently
// stopped every ring Dart learned about a minute or more late - an overdue
// ring after a reboot, or a ring opened from its notification after 87 s
// (reproduced on a real phone, 2026-10-19) - with no ring screen and no QR
// gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';

void main() {
  group('isAlarmStale', () {
    test('an alarm from a month ago is stale', () {
      final now = DateTime(2026, 9, 8, 7, 0);
      final event = DateTime(2026, 8, 8, 7, 0);
      expect(isAlarmStale(event, now), isTrue);
    });

    test('an alarm from a coincidentally-matching day/hour/minute in a '
        'different month is still recognized as stale', () {
      // Regression check for the bug this function replaced: the old logic
      // only compared day/hour/minute, so this exact case was missed.
      final now = DateTime(2026, 9, 8, 7, 30);
      final event = DateTime(2026, 8, 8, 7, 30);
      expect(isAlarmStale(event, now), isTrue);
    });

    test('an alarm a few minutes in the future is not stale', () {
      final now = DateTime(2026, 9, 8, 7, 0);
      final event = DateTime(2026, 9, 8, 7, 5);
      expect(isAlarmStale(event, now), isFalse);
    });

    test('an alarm at exactly the current minute is not stale', () {
      final now = DateTime(2026, 9, 8, 7, 0, 45);
      final event = DateTime(2026, 9, 8, 7, 0, 0);
      expect(isAlarmStale(event, now), isFalse);
    });

    test('T-232: a ring noticed 87 seconds late is not stale', () {
      final event = DateTime(2026, 9, 8, 7, 0);
      expect(isAlarmStale(event, event.add(const Duration(seconds: 87))),
          isFalse);
    });

    test('T-232: an alarm up to the overdue window late is not stale', () {
      final event = DateTime(2026, 9, 8, 7, 0);
      expect(isAlarmStale(event, event.add(const Duration(minutes: 59))),
          isFalse);
      expect(isAlarmStale(event, event.add(overdueRingWindow)), isFalse,
          reason: 'the plugin and the native siren count exactly 60 '
              'minutes as still within the window');
    });

    test('T-232: an alarm more than the overdue window late is stale', () {
      final event = DateTime(2026, 9, 8, 7, 0);
      expect(
          isAlarmStale(event,
              event.add(overdueRingWindow + const Duration(minutes: 1))),
          isTrue);
    });
  });
}
