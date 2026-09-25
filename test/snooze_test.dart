import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/snooze.dart';

// docs/scheduling-v2-spec.md FR-20, docs/TODO.md T-138.
//
// The numbers come from the requirement's worked-out test cases, not from
// the code.

DateTime at(int h, int m) => DateTime(2026, 9, 14, h, m);

void main() {
  const fiveMinutes = Duration(minutes: 5);
  const thirtyMinutes = Duration(minutes: 30);

  group('FR-20: the budget is durationToWakeUp', () {
    test('possible from the first press', () {
      expect(
        canSnooze(
          now: at(6, 0),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: thirtyMinutes,
          snoozeEnabled: true,
        ),
        isTrue,
      );
    });

    test('the last postponement hits the limit exactly and is allowed', () {
      // 06:25 + 5min = 06:30 = 06:00 + 30min -> allowed (inclusive).
      expect(
        canSnooze(
          now: at(6, 25),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: thirtyMinutes,
          snoozeEnabled: true,
        ),
        isTrue,
      );
    });

    test('one minute over is no longer allowed', () {
      // 06:26 + 5min = 06:31 > 06:30.
      expect(
        canSnooze(
          now: at(6, 26),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: thirtyMinutes,
          snoozeEnabled: true,
        ),
        isFalse,
      );
    });

    test('the budget counts from the ORIGINAL wake call, not the last press',
        () {
      // Letting it ring until 06:28 saves nothing: 06:33 > 06:30.
      expect(
        canSnooze(
          now: at(6, 28),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: thirtyMinutes,
          snoozeEnabled: true,
        ),
        isFalse,
      );
    });

    test('never possible when switched off', () {
      expect(
        canSnooze(
          now: at(6, 0),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: thirtyMinutes,
          snoozeEnabled: false,
        ),
        isFalse,
      );
    });

    test('zero budget means no snooze - the default', () {
      expect(
        canSnooze(
          now: at(6, 0),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: Duration.zero,
          snoozeEnabled: true,
        ),
        isFalse,
        reason: 'durationToWakeUp = 00:00 is the default; with no budget '
            'there is nothing to postpone',
      );
    });

    test('exactly six postponements at 30/5', () {
      var now = at(6, 0);
      var count = 0;
      while (canSnooze(
        now: now,
        originalRing: at(6, 0),
        snoozeTime: fiveMinutes,
        wakeUpBudget: thirtyMinutes,
        snoozeEnabled: true,
      )) {
        now = snoozedRingTime(now: now, snoozeTime: fiveMinutes);
        count++;
        if (count > 20) break; // guard against an infinite loop in the test
      }
      expect(count, 6);
      expect(now, at(6, 30), reason: 'the last postponement ends at the budget');
    });
  });
}
