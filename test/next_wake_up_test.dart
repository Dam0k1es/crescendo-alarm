import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/scheduling/next_wake_up.dart';

// docs/TODO.md T-66: Ersatz für Scheduler.nextAlarmTime(), von dem
// scheduleSleepReminder() (FR-16 Checkpoint 2) abhängt - Phase 6 würde die
// alte Scheduler-Klasse löschen. Der Ersatz muss BEIDE Quellen
// berücksichtigen: scheduling-v2s geplante Tageswerte UND manuelle Alarme.
// Letzteres ist kein FR-15-Verstoß: FR-15 verbietet der *Planungslogik*,
// ManualAlarms anzufassen - eine Schlafenszeit-Erinnerung darf sie lesen,
// sonst würde sie für Nutzer, die nur manuelle Alarme stellen, ins Leere
// planen.

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

void main() {
  group('nextWakeUpTime (T-66)', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('nur geplante v2-Werte -> der früheste zukünftige', () {
      final soon = DateTime(2026, 3, 11, 7, 0);
      final later = DateTime(2026, 3, 12, 6, 30);

      final result = nextWakeUpTime(
        pendingDayValues: {
          _iso(soon): soon.millisecondsSinceEpoch,
          _iso(later): later.millisecondsSinceEpoch,
        },
        manualAlarms: const [],
        now: now,
      );

      expect(result, soon);
    });

    test('vergangene und null-Werte werden ignoriert', () {
      final past = DateTime(2026, 3, 9, 7, 0);
      final future = DateTime(2026, 3, 11, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {
          _iso(past): past.millisecondsSinceEpoch,
          '2026-03-10': null,
          _iso(future): future.millisecondsSinceEpoch,
        },
        manualAlarms: const [],
        now: now,
      );

      expect(result, future);
    });

    test('nur ManualAlarm, Uhrzeit heute noch zukünftig -> heute', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 8, minute: 15))],
        now: now, // 06:00
      );

      expect(result, DateTime(2026, 3, 10, 8, 15));
    });

    test('nur ManualAlarm, Uhrzeit heute schon vorbei -> morgen', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 5, minute: 0))],
        now: now, // 06:00
      );

      expect(result, DateTime(2026, 3, 11, 5, 0));
    });

    test('beide Quellen, geplanter Wert ist früher -> geplanter Wert', () {
      final planned = DateTime(2026, 3, 10, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 9, minute: 0))],
        now: now,
      );

      expect(result, planned);
    });

    test('beide Quellen, ManualAlarm ist früher -> ManualAlarm gewinnt', () {
      final planned = DateTime(2026, 3, 11, 7, 0);

      final result = nextWakeUpTime(
        pendingDayValues: {_iso(planned): planned.millisecondsSinceEpoch},
        manualAlarms: [ManualAlarm(time: const TimeOfDay(hour: 6, minute: 30))],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 6, 30));
    });

    test('mehrere ManualAlarms -> der früheste zählt', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {},
        manualAlarms: [
          ManualAlarm(time: const TimeOfDay(hour: 9, minute: 0)),
          ManualAlarm(time: const TimeOfDay(hour: 7, minute: 45)),
        ],
        now: now,
      );

      expect(result, DateTime(2026, 3, 10, 7, 45));
    });

    test('keine Quelle liefert etwas -> null', () {
      final result = nextWakeUpTime(
        pendingDayValues: const {'2026-03-11': null},
        manualAlarms: const [],
        now: now,
      );

      expect(result, isNull);
    });
  });
}
