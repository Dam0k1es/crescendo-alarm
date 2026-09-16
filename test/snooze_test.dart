import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/alarms/snooze.dart';

// docs/scheduling-v2-spec.md FR-20, docs/TODO.md T-138.
//
// Die Zahlen stammen aus den durchgerechneten Testfaellen der Anforderung,
// nicht aus dem Code.

DateTime at(int h, int m) => DateTime(2026, 9, 14, h, m);

void main() {
  const fiveMinutes = Duration(minutes: 5);
  const thirtyMinutes = Duration(minutes: 30);

  group('FR-20: das Budget ist durationToWakeUp', () {
    test('vom ersten Druck an moeglich', () {
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

    test('die letzte Verschiebung trifft die Grenze genau und ist erlaubt', () {
      // 06:25 + 5min = 06:30 = 06:00 + 30min -> erlaubt (einschliesslich).
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

    test('eine Minute darueber ist nicht mehr erlaubt', () {
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

    test('das Budget zaehlt ab dem URSPRUNGSruf, nicht ab dem letzten Druck',
        () {
      // Wer bis 06:28 klingeln laesst, hat nichts gespart: 06:33 > 06:30.
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

    test('abgeschaltet ist nie moeglich', () {
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

    test('Budget null heisst kein Snooze - die Voreinstellung', () {
      expect(
        canSnooze(
          now: at(6, 0),
          originalRing: at(6, 0),
          snoozeTime: fiveMinutes,
          wakeUpBudget: Duration.zero,
          snoozeEnabled: true,
        ),
        isFalse,
        reason: 'durationToWakeUp = 00:00 ist die Vorgabe; ohne Budget gibt es '
            'nichts zu verschieben',
      );
    });

    test('genau sechs Verschiebungen bei 30/5', () {
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
        if (count > 20) break; // Schutz gegen eine Endlosschleife im Test
      }
      expect(count, 6);
      expect(now, at(6, 30), reason: 'die letzte Verschiebung endet am Budget');
    });
  });
}
