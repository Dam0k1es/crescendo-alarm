// An alarm set in the past must be recognized as stale so Handler.handleAlarm
// stops it instead of showing an overlay. This is pure logic with no UI/device
// dependency, so a plain unit test is more appropriate than a full
// integration_test - see integration_test/app_test.dart for the device-driven
// scenarios, and docs/TODO.md for the full E2E coverage picture.

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';

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

    test('an alarm one minute in the past is stale', () {
      final now = DateTime(2026, 9, 8, 7, 1);
      final event = DateTime(2026, 9, 8, 7, 0);
      expect(isAlarmStale(event, now), isTrue);
    });
  });
}
